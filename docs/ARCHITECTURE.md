# Architecture Overview

This document describes the technical architecture of **oasis-app**: how layers interact, how messages are secured, and how the native libp2p library plugs into Flutter.

---

## High-Level Layer Diagram

```
┌──────────────────────────────────────────────────────────┐
│                     Flutter App                          │
│                                                          │
│  screens/         UI — MaterialApp, Riverpod ConsumerWidget
│  providers/       State management (Riverpod 2.x)       │
│  services/        Business logic                        │
│  repositories/    Abstractions + mock/native impls      │
│  models/          Pure data classes (Message, Contact…) │
│                                                          │
│  p2p_bridge.dart ──────────────────► dart:ffi           │
└────────────────────────┬─────────────────────────────────┘
                         │ C ABI (dart:ffi)
┌────────────────────────▼─────────────────────────────────┐
│  Native libp2p library  (from oasis-node/mobile/)        │
│                                                          │
│  iOS:     P2P.xcframework  (arm64, static)               │
│  Android: libp2p.so        (arm64-v8a, armeabi-v7a)      │
│                                                          │
│  Exported C symbols:                                     │
│    P2P_Initialize  P2P_ConnectToPeer  P2P_SendToRelay    │
│    P2P_SendDirect  P2P_FindPeer       P2P_Sign           │
│    P2P_Verify      P2P_PublicKeyFromPeerID  P2P_Close    │
│    P2P_DHTProvide  P2P_DHTFindProviders     …            │
└────────────────────────┬─────────────────────────────────┘
                         │ libp2p protocols over QUIC/TCP
┌────────────────────────▼─────────────────────────────────┐
│  oasis-node  (relay/store-and-forward server)            │
│  Deployed on VPS or Raspberry Pi                        │
│                                                          │
│  /oasis-node/store/1.0.0     ← store encrypted message  │
│  /oasis-node/retrieve/1.0.0  ← poll for messages        │
│  BadgerDB  (TTL 24 h)                                    │
│  Public mode  or  PSK-isolated private mode             │
└──────────────────────────────────────────────────────────┘
```

---

## Service Layer

| Service | File | Responsibility |
|---|---|---|
| `P2PBridge` | `services/p2p_bridge.dart` | dart:ffi bindings — loads native library, binds all C symbols, manages Isolate |
| `P2PService` | `services/p2p_service.dart` | High-level messaging — send, poll, retry queue, call signaling |
| `IdentityService` | `services/identity_service.dart` | Ed25519 PeerID, X25519 keypair, secure storage, sign/verify delegation |
| `CryptoService` | `services/crypto_service.dart` | X25519 ECDH shared-secret derivation + ChaCha20-Poly1305 AEAD |
| `StorageService` | `services/storage_service.dart` | Hive AES-256 boxes — messages, contacts, nonces |
| `AuthService` | `services/auth_service.dart` | Biometric / PIN lock |
| `CallService` | `services/call_service.dart` | WebRTC session management, ICE/SDP signaling over relay |
| `NetworkService` | `services/network_service.dart` | Public / private network switching, active network state |
| `BootstrapNodesService` | `services/bootstrap_nodes_service.dart` | Persistent list of discovered Oasis nodes (with blacklisting) |
| `MyNodesService` | `services/my_nodes_service.dart` | User's own relay nodes (priority connection) |
| `PrivateNetworkSetupService` | `services/private_network_setup_service.dart` | PSK storage and private network bootstrap multiaddr |
| `DnsaddrResolver` | `services/dnsaddr_resolver.dart` | Resolves `/dnsaddr/` entries to concrete TCP multiaddrs (iOS workaround) |

---

## Identity and Keys

Every user has **two separate keypairs**:

| Keypair | Algorithm | Purpose |
|---|---|---|
| Identity keypair | Ed25519 | PeerID derivation, message signing via `P2P_Sign`, relay authentication |
| Encryption keypair | X25519 | ECDH key exchange, deriving ChaCha20 shared secret |

Both keys are generated once on first launch and persisted in the OS Keychain (iOS) / KeyStore (Android) via `flutter_secure_storage`.

The **PeerID** is the SHA-256 multihash of the Ed25519 public key — encoded as a base58btc CIDv1 string. It is the stable user address that appears in QR codes and is shared to add contacts.

### Signing

`IdentityService.sign()` delegates to `P2PBridge.sign()` which calls the native `P2P_Sign` symbol. Signing happens inside Go/libp2p so the produced signature is bit-for-bit compatible with libp2p's `pub.Verify()` on the relay node side.

### Verification

`P2PService._processReceivedMessage()` calls `_repository.verify(peerID, data, signature)` which calls `P2P_Verify` via FFI. The sender's Ed25519 public key is recovered from the PeerID string inside the Go layer — no separate key transport needed for verification.

---

## Message Flow

### Sending

```
sendMessage()
  │
  ├─ encrypt plaintext
  │    X25519 ECDH → shared secret → ChaCha20-Poly1305
  │
  ├─ build Message envelope
  │    id, senderPeerID, targetPeerID, ciphertext,
  │    senderPublicKey (X25519), nonce, timestamps
  │
  ├─ sign  message.signableData  via P2P_Sign (native)
  │
  ├─ save to local Hive (status = pending)
  │
  └─ _sendViaRelay()
       P2P_SendToRelay → /oasis-node/store/1.0.0
       on success: update status = sent
       on failure: keep status = failed (retry later)
```

### Receiving (polling loop)

```
_pollMessages()  [Timer, every N seconds]
  │
  ├─ P2P_SendToRelay → /oasis-node/retrieve/1.0.0
  │    returns JSON array of Message envelopes
  │
  └─ for each message → _processReceivedMessage()
       │
       ├─ call_signal?  → forward to CallService, delete from relay
       │
       ├─ nonce check   → replay protection (seen nonces in Hive)
       │
       ├─ P2P_Verify    → Ed25519 signature over signableData
       │
       ├─ decrypt ciphertext
       │    X25519 ECDH (sender pub + own priv) → ChaCha20-Poly1305
       │
       ├─ handle by ContentType
       │    text / audio / image / profile_update / call_signal / …
       │
       └─ save to local Hive, delete from relay, notify UI stream
```

---

## Encryption Details

```
Shared secret derivation:
  ECDH(senderPrivateKey_x25519, recipientPublicKey_x25519)
  → 32-byte shared secret

Encryption:
  ChaCha20-Poly1305 AEAD
  key  = shared secret
  nonce = random 12 bytes (included in message envelope)
  AAD  = none

Wire format (ciphertext field):
  [12 bytes nonce][N bytes ciphertext][16 bytes Poly1305 MAC]
```

Relay nodes receive the ciphertext field only — they never see plaintext or encryption keys.

---

## Replay Protection

Every outgoing message includes a random 16-byte **nonce**. On receipt:

1. The nonce is base64-encoded and looked up in the `seen_nonces` Hive box.
2. If already present → message is silently discarded and deleted from the relay.
3. If new → nonce is stored. Old nonces are cleaned up after the message TTL (24 h).

---

## Private Networks (PSK) *(coming soon)*

> This feature is not yet available in the current release. The architecture and code scaffolding are in place but the feature is not exposed in the UI.

When a user creates or joins a private network:

- A random 32-byte **PSK** (pre-shared key) is generated (or scanned via QR code).
- The PSK is passed to `P2P_Initialize` as a hex string.
- libp2p uses it to configure a private network swarm — only peers presenting the same PSK can communicate.
- Messages and relay nodes are isolated: a private-network node rejects public-network peers.
- The PSK is stored in the OS Keychain under `psk_network_{networkId}`.

---

## Connection Management

The app maintains **one active relay node connection** at a time:

1. On startup, candidate Oasis nodes are collected from:
   - `MyNodesService` (user's own nodes — highest priority)
   - `BootstrapNodesService` (discovered nodes from DHT)
   - `app_config.dart` `bootstrapNodes` list (well-known public nodes)
2. The list is shuffled (privacy + load balancing) and tried sequentially.
3. The first successful connection becomes `_activeBootstrapNode`.
4. Failed connections are blacklisted (discovered nodes only).
5. A reconnect timer retries every 30 s if no node is reachable.
6. Node health is tracked via `_nodeHealthScores`; after `_maxConsecutiveFailures` the node triggers failover.

---

## FFI Threading

`P2P_Initialize` starts a background Go goroutine scheduler. All subsequent FFI calls are **synchronous** from Dart's perspective but execute on Go's internal thread pool.

Long-running calls (node connect, DHT queries) are wrapped in `Future` + `timeout` to avoid blocking the main isolate. The polling loop uses an `_isPolling` guard flag to prevent overlapping calls.

---

## Voice Calls *(coming soon)*

> This feature is not yet available in the current release. The signaling infrastructure (`CallService`, `call_signal` message type, fast polling) is implemented but the call UI is not yet shipped.

Calls use **WebRTC** for media transport with the relay node used for ICE/SDP signaling:

```
Caller                        Relay Node                     Callee
  │── sendCallSignal(offer) ──►│                               │
  │                            │◄── poll ──────────────────────│
  │                            │── deliver offer ─────────────►│
  │◄── sendCallSignal(answer) ─│◄──────────────────────────────│
  │                            │  (ICE candidates exchanged)   │
  │◄═══════════ WebRTC media (DTLS-SRTP, P2P or TURN) ════════►│
```

The app enables **fast polling** (1 s interval) during active call signaling and reverts to the normal interval once the call is established.

---

## Local Storage

| Hive Box | Contents | Encryption |
|---|---|---|
| `messages` | Message envelopes (with local plaintext) | AES-256 |
| `contacts` | PeerID, display name, X25519 pub key, node multiaddr | AES-256 |
| `seen_nonces` | Nonce strings for replay protection | AES-256 |
| `settings` | User preferences, active network | AES-256 |

The AES-256 Hive key is generated once and stored in the OS Keychain / KeyStore via `flutter_secure_storage`. The database files are excluded from iCloud/Google backups.

---

## State Management

All runtime state is managed with **Riverpod 2.x**:

- `AsyncNotifierProvider` for services with async initialization (`P2PService`, `StorageService`, …)
- `StreamProvider` for the live message stream from `P2PService.messageStream`
- `StateNotifierProvider` for UI state (chat list, call state, auth state)

Services are injected through provider constructors — no global singletons. The `providers/` directory contains the generated `.g.dart` files (build_runner + riverpod_generator).

---

## Related Documentation

| Doc | Topic |
|---|---|
| [CONFIG_GUIDE.md](CONFIG_GUIDE.md) | Bootstrap nodes, environment configs |
| [STORAGE_ENCRYPTION.md](STORAGE_ENCRYPTION.md) | Hive AES-256 details |
| [DHT_POLLING_EXPLAINED.md](DHT_POLLING_EXPLAINED.md) | DHT internals, FFI threading |
| [BACKGROUND_SYNC_GUIDE.md](BACKGROUND_SYNC_GUIDE.md) | WorkManager background polling |
| [ERROR_HANDLING_README.md](ERROR_HANDLING_README.md) | Result type, error taxonomy |
| [IOS_BUILD_FIX.md](IOS_BUILD_FIX.md) | xcframework linker flags |
