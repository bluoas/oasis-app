# Mock Implementations for Unit Testing

This directory contains mock implementations of all service interfaces, allowing comprehensive unit testing without native dependencies (FFI, libp2p, Hive, SecureStorage).

## 📦 Available Mocks

### `p2p_mock_repository.dart`
**Purpose:** Mock P2P native bridge (libp2p via FFI)

**Features:**
- Simulates network delays (10-150ms)
- Configurable error scenarios
- Pre-configure peer addresses, public keys, DHT providers
- Track operations for verification

**Usage:**
```dart
final mock = P2PMockRepository();
await mock.initialize(privateKey);
mock.registerPeer('peer_123', '/ip4/127.0.0.1/tcp/4001');
await mock.connectToRelay(relayAddr);
```

---

### `crypto_mock_service.dart`
**Purpose:** Mock cryptographic operations

**Features:**
- Deterministic key generation
- Fast "encryption" (base64, NOT secure)
- Track crypto operation counts
- Configurable failures

**Usage:**
```dart
final mock = CryptoMockService();
final keyPair = await mock.generateX25519KeyPair();
final encrypted = await mock.encrypt(plaintext: 'test', ...);
```

---

### `storage_mock_service.dart`
**Purpose:** In-memory storage (no Hive)

**Features:**
- Full Storage interface implementation
- Messages and contacts stored in memory
- Fast operations (2-5ms delays)
- Track call counts

**Usage:**
```dart
final mock = StorageMockService();
await mock.initialize();
await mock.saveMessage(message);
final messages = await mock.getMessagesForPeer('peer_123');
```

---

### `identity_mock_service.dart`
**Purpose:** Mock identity management

**Features:**
- Pre-configure test identities
- Generate deterministic keys via CryptoMockService
- No secure storage dependency

**Usage:**
```dart
final cryptoMock = CryptoMockService();
final mock = IdentityMockService(crypto: cryptoMock);
await mock.createTestIdentity('alice');
print(mock.peerID); // 'test_peer_alice...'
```

---

## 🎯 Testing Patterns

### 1. Basic Mock Setup
```dart
test('my test', () async {
  final mockRepo = P2PMockRepository();
  final mockCrypto = CryptoMockService();
  final mockStorage = StorageMockService();
  final mockIdentity = IdentityMockService(crypto: mockCrypto);
  
  await mockStorage.initialize();
  await mockIdentity.createTestIdentity();
  
  final service = P2PService(
    repository: mockRepo,
    crypto: mockCrypto,
    identity: mockIdentity,
    storage: mockStorage,
  );
  
  // Test service logic
});
```

### 2. Riverpod Override Pattern
```dart
test('with provider override', () {
  final container = ProviderContainer(
    overrides: [
      p2pRepositoryProvider.overrideWithValue(P2PMockRepository()),
      cryptoServiceProvider.overrideWithValue(CryptoMockService()),
      // ... other overrides
    ],
  );
  
  final service = container.read(p2pServiceProvider);
  // Test with real provider graph
});
```

### 3. Error Scenario Testing
```dart
test('handle network failure', () async {
  final mock = P2PMockRepository();
  mock.shouldFailConnectToRelay = true;
  
  expect(
    () => service.connectToRelay(addr),
    throwsException,
  );
});
```

### 4. Pre-configured State
```dart
test('with predefined peers', () {
  final mock = P2PMockRepository();
  mock.registerPeer('peer_alice', '/ip4/1.2.3.4/tcp/4001');
  mock.registerPublicKey('peer_alice', alicePublicKey);
  
  // Now findPeer('peer_alice') returns configured address
});
```

---

## 🔧 Mock Configuration Options

### P2PMockRepository
```dart
mock.shouldFailInitialize = true;
mock.shouldFailConnectToRelay = true;
mock.shouldFailSendToRelay = true;
mock.shouldFailSendDirect = true;
mock.shouldFailDhtProvide = true;

mock.mockSendToRelayResponse = '{"custom": "response"}';
mock.mockFindProvidersResult = ['peer1', 'peer2'];
```

### CryptoMockService
```dart
mock.shouldFailEncrypt = true;
mock.shouldFailDecrypt = true;
mock.shouldFailSign = true;
mock.shouldFailVerify = true;
```

### StorageMockService
```dart
mock.shouldFailInitialize = true;
mock.shouldFailSaveMessage = true;
mock.shouldFailSaveContact = true;
```

### IdentityMockService
```dart
mock.shouldFailInitialize = true;
mock.shouldFailGenerate = true;
mock.shouldFailLoad = true;
mock.shouldFailSign = true;
mock.shouldFailVerify = true;
```

---

## 📊 Verification Helpers

All mocks provide counters and state inspection:

```dart
// Operation counts
expect(mockCrypto.encryptCallCount, equals(2));
expect(mockStorage.saveMessageCallCount, greaterThan(0));

// State inspection
expect(mockRepository.isInitialized, isTrue);
expect(mockStorage.messageCount, equals(5));
expect(mockIdentity.hasIdentity, isTrue);

// Stored data
expect(mockRepository.connectedRelays, contains(relayAddr));
expect(mockStorage.allMessageIds, hasLength(3));
```

---

## 🔄 Cleanup Between Tests

Always reset mocks in `tearDown()`:

```dart
tearDown(() {
  mockRepository.reset();
  mockCrypto.reset();
  mockStorage.reset();
  mockIdentity.reset();
});
```

This ensures:
- No state leakage between tests
- Fresh counters
- Disabled error scenarios
- Cleared pre-configured data

---

## ⚡ Performance

Mock operations are **10-100x faster** than native:

| Operation | Native | Mock |
|-----------|--------|------|
| Initialize P2P | ~500ms | ~10ms |
| Encrypt/Decrypt | ~50ms | ~5ms |
| Storage ops | ~20ms | ~3ms |
| DHT lookup | ~5s | ~150ms |

**100 tests:** ~10 minutes (native) → **~5 seconds (mocked)**

---

## 🎓 Best Practices

1. **Unit tests = Mocks only**
   - Test business logic in isolation
   - No network, no FFI, no native storage

2. **Integration tests = Native implementations**
   - Test real crypto, real P2P, real storage
   - Run on device/simulator only

3. **Mock what you don't own**
   - Mock native bridge (FFI)
   - Mock external storage (Hive, SecureStorage)
   - Don't mock your own models/DTOs

4. **Keep mocks simple**
   - Return deterministic results
   - Simulate only essential behavior
   - Don't replicate complex logic

---

## 📁 File Structure

```
test/
├── mocks/
│   ├── p2p_mock_repository.dart
│   ├── crypto_mock_service.dart
│   ├── storage_mock_service.dart
│   ├── identity_mock_service.dart
│   └── README.md (this file)
├── p2p_service_test.dart (example tests)
└── widget_test.dart
```

---

## 🚀 Quick Start

```bash
# Run all tests with mocks
flutter test

# Run specific test file
flutter test test/p2p_service_test.dart

# Run with coverage
flutter test --coverage
```

See `test/p2p_service_test.dart` for complete usage examples.
