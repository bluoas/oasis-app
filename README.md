# Oasis App

A decentralized, end-to-end encrypted messaging app for iOS and Android built on [libp2p](https://libp2p.io/). No central servers. No metadata. Direct peer-to-peer when both users are online, store-and-forward via oasis nodes network when offline.

---

## Features

- **Serverless P2P messaging** — libp2p embedded directly in the app via gomobile FFI
- **End-to-end encryption** — X25519 key exchange + ChaCha20-Poly1305
- **Encrypted local storage** — Hive database with AES-256, key held in OS Keychain/KeyStore
- **Voice calls** *(coming soon)* — WebRTC-based encrypted calls
- **Audio & image messages** — E2E encrypted media transfer
- **Private networks** *(coming soon)* — PSK-based isolated networks (invite-only via QR code)
- **Contact management** — Identity via libp2p Ed25519 PeerID, added via QR code scan
- **Background sync** — WorkManager-based background message polling
- **Auth lock** — Biometric/PIN lock screen on resume

---

## Related Repositories

The Oasis ecosystem consists of two repositories that work together:

| Repository | Description |
|---|---|
| **oasis-app** ← you are here | Flutter mobile app (iOS + Android) |
| [**oasis-node**](https://github.com/your-org/oasis-node) | Go relay/store-and-forward node + gomobile FFI bridge |

The `oasis-node` repo serves two purposes:
1. **Relay node** — a standalone Go server you deploy on a VPS/Raspberry Pi. Stores encrypted messages for offline users and helps with NAT traversal. No plaintext ever leaves the app.
2. **Mobile FFI library** — the `mobile/` package in that repo compiles libp2p into `P2P.xcframework` (iOS) and `libp2p.so` (Android) via CGO. These artifacts are what the Flutter app links against.

---

## Architecture

```
┌─────────────────────────────────────────────┐
│          oasis-app (this repo)               │
│              Flutter App                     │
│                                             │
│  screens/         ← UI Layer                │
│  providers/       ← State (Riverpod)        │
│  services/        ← Business Logic          │
│  repositories/    ← Abstractions + Mocks    │
│  models/          ← Data Models             │
│                                             │
│  p2p_bridge.dart  ← FFI → native library    │
└──────────────┬──────────────────────────────┘
               │ dart:ffi
┌──────────────▼──────────────────────────────┐
│  oasis-node/mobile/ (libp2p, CGO)            │
│  P2P.xcframework (iOS) / libp2p.so (Android) │
│                                             │
│  • Ed25519 Identity                         │
│  • Kademlia DHT                             │
│  • QUIC/TCP transport                       │
│  • NAT traversal                            │
└──────────────┬──────────────────────────────┘
               │
    ┌──────────▼──────────────────────┐
    │   oasis-node (relay server)     │
    │   deployed on VPS / Raspberry Pi│
    │                                 │
    │   • Store-and-forward           │
    │   • BadgerDB, TTL 24h           │
    │   • Public or PSK private mode  │
    └─────────────────────────────────┘
```

**Message flow:**
- Both online → relay node handles NAT traversal, then proxies the encrypted stream between devices
- Recipient offline → message stored encrypted on relay node (BadgerDB, TTL 24h), fetched via DHT polling on next app start
- The relay node **always** acts as intermediary on mobile — smartphones sit behind carrier NAT/CGNAT and cannot accept direct incoming connections
- Relay nodes see only ciphertext, never plaintext or metadata

---

## Prerequisites

| Tool | Version |
|------|---------|
| Flutter | ≥ 3.10 (beta channel) |
| Dart SDK | ^3.10.0 |
| Xcode | ≥ 15 (iOS builds) |
| CocoaPods | ≥ 1.14 |
| Android Studio / NDK | latest stable |
| gomobile | for rebuilding the native library |

---

## Setup

### 1. Clone and install dependencies

```bash
git clone https://github.com/your-org/oasis-app.git
cd oasis-app
flutter pub get
```

### 2. Code generation (Riverpod)

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 3. Build and place the native P2P library

The app requires a prebuilt native library from the `oasis-node` repo:

```bash
# Clone the node repo alongside this one
git clone https://github.com/your-org/oasis-node.git
cd oasis-node

# Build iOS library (requires Xcode + Go 1.23+)
make mobile-ios
# Output: mobile/build/ios/device/libp2p.a + P2P.xcframework

# Build Android libraries (requires Android NDK 27.0.12077973)
make mobile-android
# Output: mobile/build/android/arm64/libp2p.so
#         mobile/build/android/armeabi-v7a/libp2p.so
```

Then copy the artifacts into this repo:

```bash
# iOS
cp -r mobile/build/ios/device/P2P.xcframework ../oasis-app/ios/

# Android
cp mobile/build/android/arm64/libp2p.so     ../oasis-app/android/app/src/main/jniLibs/arm64-v8a/
cp mobile/build/android/armeabi-v7a/libp2p.so ../oasis-app/android/app/src/main/jniLibs/armeabi-v7a/
```

> The NDK version `27.0.12077973` is required for Android. Set `ANDROID_HOME` and `NDK_PATH` accordingly before building.

---

## Building for iOS

> **Simulator is not supported.** The xcframework targets `arm64` (real devices only).

### First-time setup

```bash
cd ios
pod install
cd ..
```

### Run on device (debug)

```bash
flutter run -d <device-id>
```

List connected devices: `flutter devices`

### Release build

```bash
flutter build ios --release
```

Then open `ios/Runner.xcworkspace` in Xcode, select your provisioning profile, and archive via **Product → Archive**.

### Linker fix (if symbols not found)

If you see `symbol not found: _P2P_Initialize` at runtime, add this to `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig`:

```xcconfig
OTHER_LDFLAGS = $(inherited) -force_load $(PROJECT_DIR)/P2P.xcframework/ios-arm64/libp2p.a -framework Security -lresolv
```

Then run `flutter clean && cd ios && pod install && cd ..` and rebuild.

---

## Building for Android

### Run on device (debug)

```bash
flutter run -d <device-id>
```

### Debug APK

```bash
flutter build apk --debug
```

### Release APK

```bash
flutter build apk --release
```

### Play Store bundle

```bash
flutter build appbundle --release
```

> Set up a signing config in `android/app/build.gradle.kts` before publishing. The current config uses debug keys as a placeholder.

---

## Project Structure

```
lib/
├── main.dart                        # Entry point, app initialization
├── config/
│   ├── app_config.dart              # Bootstrap nodes, timeouts, feature flags
│   └── app_theme.dart               # Colors, typography
├── models/                          # Pure data classes (Message, Contact, Call, ...)
├── providers/                       # Riverpod providers + generated .g.dart files
├── repositories/                    # Interfaces (IP2PRepository) + native impl
├── services/
│   ├── p2p_bridge.dart              # FFI bindings to gomobile library
│   ├── p2p_service.dart             # High-level P2P logic, DHT polling
│   ├── crypto_service.dart          # X25519 + ChaCha20-Poly1305
│   ├── identity_service.dart        # Ed25519 keypair, PeerID, SecureStorage
│   ├── storage_service.dart         # Hive AES-256 boxes
│   ├── auth_service.dart            # Biometric / PIN auth
│   ├── call_service.dart            # WebRTC call management
│   └── network_service.dart         # Public / private network switching
├── screens/                         # All UI screens
├── utils/                           # Result type, error helpers
└── widgets/                         # Shared UI components
```

---

## Configuration

Bootstrap nodes and environment settings live in `lib/config/app_config.dart`. The app automatically uses `AppConfig.development()` in debug builds and `AppConfig.production()` in release builds — no manual switching needed.

To add or change relay/bootstrap nodes, edit the `bootstrapNodes` list. The app uses hash-based cache invalidation, so changes take effect on the next launch without requiring a reinstall.

See [docs/CONFIG_GUIDE.md](docs/CONFIG_GUIDE.md) for details.

---

## Documentation

| Doc | Description |
|-----|-------------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Detailed architecture overview |
| [docs/CONFIG_GUIDE.md](docs/CONFIG_GUIDE.md) | Build modes and configuration |
| [docs/STORAGE_ENCRYPTION.md](docs/STORAGE_ENCRYPTION.md) | Local data encryption |
| [docs/ERROR_HANDLING_README.md](docs/ERROR_HANDLING_README.md) | Error handling patterns |
| [docs/BACKGROUND_SYNC_GUIDE.md](docs/BACKGROUND_SYNC_GUIDE.md) | Background message polling |
| [docs/DHT_POLLING_EXPLAINED.md](docs/DHT_POLLING_EXPLAINED.md) | DHT architecture and FFI threading |
| [docs/IOS_BUILD_FIX.md](docs/IOS_BUILD_FIX.md) | iOS linker troubleshooting |

---

## Running a Oasis Node

To run your own oasis node (for private networks or self-hosting), see the [oasis-node](https://github.com/your-org/oasis-node) repository. Quick start:

```bash
# Public mode (for testing)
./build/oasis-node --public -relay -store

# Private network mode (auto-generates PSK)
./build/oasis-node --private -relay -store

# Docker
./deploy.sh public
```


## Contributing

1. Fork the repo and create a feature branch
2. Run `dart run build_runner build` after changing providers
3. Run `flutter test` before submitting a PR
4. For native library changes, rebuild via `make mobile-ios` / `make mobile-android` in the `oasis-node` repo and copy the artifacts as described in Setup

---

## License

See [LICENSE](LICENSE).
