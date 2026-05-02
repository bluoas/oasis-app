import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import '../lib/models/message.dart';
import '../lib/models/contact.dart';
import '../lib/models/app_error.dart';
import 'mocks/p2p_mock_repository.dart';
import 'mocks/crypto_mock_service.dart';
import 'mocks/storage_mock_service.dart';
import 'mocks/identity_mock_service.dart';

/// Example Unit Tests for Mock Implementations
/// 
/// Demonstrates how to use mock implementations for testing
/// without native dependencies (FFI, libp2p, Hive, SecureStorage)
void main() {
  group('P2PMockRepository Tests', () {
    late P2PMockRepository repository;

    setUp(() {
      repository = P2PMockRepository();
    });

    tearDown(() {
      repository.reset();
    });

    test('initialize() should successfully initialize', () async {
      final privateKey = Uint8List.fromList(List.generate(32, (i) => i));
      
      await repository.initialize(privateKey, []);
      
      expect(repository.isInitialized, isTrue);
    });

    test('connectToRelay() should add relay to connected list', () async {
      final privateKey = Uint8List.fromList(List.generate(32, (i) => i));
      await repository.initialize(privateKey, []);
      
      const relayAddr = '/ip4/127.0.0.1/tcp/4001/p2p/QmRelay123';
      await repository.connectToRelay(relayAddr);
      
      expect(repository.connectedRelays, contains(relayAddr));
    });

    test('should fail when configured to fail', () async {
      repository.shouldFailInitialize = true;
      final privateKey = Uint8List.fromList(List.generate(32, (i) => i));
      
      expect(
        () => repository.initialize(privateKey, []),
        throwsException,
      );
    });

    test('getStatus() should return current state', () {
      expect(repository.isInitialized, isFalse);
      
      final status = repository.getStatus();
      
      expect(status['initialized'], isFalse);
      expect(status['connectedRelays'], equals(0));
    });
  });

  group('CryptoMockService Tests', () {
    late CryptoMockService crypto;

    setUp(() {
      crypto = CryptoMockService();
    });

    tearDown(() {
      crypto.reset();
    });

    test('encrypt/decrypt should be reversible', () async {
      const plaintext = 'Hello World!';
      final keyPairResult = await crypto.generateX25519KeyPair();
      expect(keyPairResult.isSuccess, isTrue);
      final keyPair = keyPairResult.valueOrNull!;
      
      final encryptedResult = await crypto.encrypt(
        plaintext: plaintext,
        recipientPublicKey: keyPair.publicKey,
        senderPrivateKey: keyPair.privateKey,
      );
      expect(encryptedResult.isSuccess, isTrue);
      final encrypted = encryptedResult.valueOrNull!;
      
      final decryptedResult = await crypto.decrypt(
        ciphertext: encrypted,
        senderPublicKey: keyPair.publicKey,
        recipientPrivateKey: keyPair.privateKey,
      );
      expect(decryptedResult.isSuccess, isTrue);
      final decrypted = decryptedResult.valueOrNull!;
      
      expect(decrypted, equals(plaintext));
      expect(crypto.encryptCallCount, equals(1));
      expect(crypto.decryptCallCount, equals(1));
    });

    test('sign() should return deterministic signature', () async {
      final keyPairResult = await crypto.generateEd25519KeyPair();
      expect(keyPairResult.isSuccess, isTrue);
      final keyPair = keyPairResult.valueOrNull!;
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      
      final signatureResult = await crypto.sign(
        data: data,
        privateKey: keyPair.privateKey,
      );
      expect(signatureResult.isSuccess, isTrue);
      final signature = signatureResult.valueOrNull!;
      
      expect(signature.length, equals(64));
      expect(crypto.signCallCount, equals(1));
    });

    test('verify() should validate signature', () async {
      final keyPairResult = await crypto.generateEd25519KeyPair();
      expect(keyPairResult.isSuccess, isTrue);
      final keyPair = keyPairResult.valueOrNull!;
      final data = Uint8List.fromList([1, 2, 3]);
      
      final signatureResult = await crypto.sign(data: data, privateKey: keyPair.privateKey);
      expect(signatureResult.isSuccess, isTrue);
      final signature = signatureResult.valueOrNull!;
      
      final isValidResult = await crypto.verify(
        data: data,
        signature: signature,
        publicKey: keyPair.publicKey,
      );
      expect(isValidResult.isSuccess, isTrue);
      final isValid = isValidResult.valueOrNull!;
      
      expect(isValid, isTrue);
    });

    test('ed25519ToX25519 conversions should work', () async {
      final ed25519KeysResult = await crypto.generateEd25519KeyPair();
      expect(ed25519KeysResult.isSuccess, isTrue);
      final ed25519Keys = ed25519KeysResult.valueOrNull!;
      
      final x25519PublicKeyResult = await crypto.ed25519PublicKeyToX25519(
        ed25519Keys.publicKey,
      );
      expect(x25519PublicKeyResult.isSuccess, isTrue);
      final x25519PublicKey = x25519PublicKeyResult.valueOrNull!;
      
      final x25519PrivateKey = await crypto.ed25519PrivateKeyToX25519(
        ed25519Keys.privateKey,
      );
      
      expect(x25519PublicKey.length, equals(32));
      expect(x25519PrivateKey.length, equals(32));
    });
  });

  group('StorageMockService Tests', () {
    late StorageMockService storage;

    setUp(() async {
      storage = StorageMockService();
      await storage.initialize();
    });

    tearDown(() {
      storage.reset();
    });

    test('saveMessage() and getMessage() should persist data', () async {
      final message = Message(
        id: 'msg_1',
        senderPeerID: 'peer_alice',
        targetPeerID: 'peer_bob',
        timestamp: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        ciphertext: Uint8List.fromList([1, 2, 3]),
        signature: Uint8List.fromList(List.generate(64, (i) => i)),
        nonce: Uint8List.fromList(List.generate(24, (i) => i)),
        plaintext: 'Test message',
      );
      
      final saveResult = await storage.saveMessage(message);
      expect(saveResult.isSuccess, isTrue);
      
      final result = await storage.getMessage('msg_1');
      expect(result.isSuccess, isTrue);
      
      final retrieved = result.valueOrNull;
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals('msg_1'));
      expect(storage.messageCount, equals(1));
    });

    test('saveContact() and getContact() should persist data', () async {
      final contact = Contact(
        peerID: 'peer_alice',
        displayName: 'Alice',
        userName: 'Alice',
        addedAt: DateTime.now(),
      );
      
      final saveResult = await storage.saveContact(contact);
      expect(saveResult.isSuccess, isTrue);
      
      final result = await storage.getContact('peer_alice');
      expect(result.isSuccess, isTrue);
      
      final retrieved = result.valueOrNull;
      expect(retrieved, isNotNull);
      expect(retrieved!.displayName, equals('Alice'));
      expect(storage.contactCount, equals(1));
    });

    test('getMessagesForPeer() should filter by peer', () async {
      final msg1 = Message(
        id: 'msg_1',
        senderPeerID: 'peer_alice',
        targetPeerID: 'peer_bob',
        timestamp: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        ciphertext: Uint8List.fromList([1, 2, 3]),
        signature: Uint8List.fromList(List.generate(64, (i) => i)),
        nonce: Uint8List.fromList(List.generate(24, (i) => i)),
      );
      
      final msg2 = Message(
        id: 'msg_2',
        senderPeerID: 'peer_charlie',
        targetPeerID: 'peer_bob',
        timestamp: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        ciphertext: Uint8List.fromList([4, 5, 6]),
        signature: Uint8List.fromList(List.generate(64, (i) => i)),
        nonce: Uint8List.fromList(List.generate(24, (i) => i)),
      );
      
      await storage.saveMessage(msg1);
      await storage.saveMessage(msg2);
      
      final result = await storage.getMessagesForPeer('peer_alice');
      expect(result.isSuccess, isTrue);
      
      final aliceMessages = result.valueOrNull!;
      expect(aliceMessages.length, equals(1));
      expect(aliceMessages.first.senderPeerID, equals('peer_alice'));
    });

    test('nonce tracking should prevent replays', () async {
      const nonceBase64 = 'abc123';
      
      final result1 = await storage.hasSeenNonce(nonceBase64);
      expect(result1.isSuccess, isTrue);
      final seen1 = result1.valueOrNull!;
      expect(seen1, isFalse);
      
      final markResult = await storage.markNonceSeen(nonceBase64);
      expect(markResult.isSuccess, isTrue);
      
      final result2 = await storage.hasSeenNonce(nonceBase64);
      expect(result2.isSuccess, isTrue);
      final seen2 = result2.valueOrNull!;
      expect(seen2, isTrue);
    });

    test('clearAll() should reset all data', () async {
      final contact = Contact(
        peerID: 'peer_test',
        displayName: 'Test',
        userName: 'Test',
        addedAt: DateTime.now(),
      );
      
      final saveResult = await storage.saveContact(contact);
      expect(saveResult.isSuccess, isTrue);
      expect(storage.contactCount, equals(1));
      
      final clearResult = await storage.clearAll();
      expect(clearResult.isSuccess, isTrue);
      
      expect(storage.messageCount, equals(0));
      expect(storage.contactCount, equals(0));
    });
  });

  group('IdentityMockService Tests', () {
    late CryptoMockService crypto;
    late IdentityMockService identity;

    setUp(() {
      crypto = CryptoMockService();
      identity = IdentityMockService(crypto: crypto);
    });

    tearDown(() {
      crypto.reset();
      identity.reset();
    });

    test('createTestIdentity() should generate identity', () async {
      expect(identity.hasIdentity, isFalse);
      
      await identity.createTestIdentity('alice');
      
      expect(identity.hasIdentity, isTrue);
      expect(identity.peerID, isNotNull);
      expect(identity.privateKey, isNotNull);
      expect(identity.publicKey, isNotNull);
    });

    test('sign() should use crypto service', () async {
      await identity.createTestIdentity();
      final data = Uint8List.fromList([1, 2, 3]);
      
      final signatureResult = await identity.sign(data);
      expect(signatureResult.isSuccess, isTrue);
      final signature = signatureResult.valueOrNull!;
      
      expect(signature.length, equals(64));
      expect(crypto.signCallCount, equals(1));
    });

    test('sign() should fail without identity', () async {
      final data = Uint8List.fromList([1, 2, 3]);
      
      final signatureResult = await identity.sign(data);
      expect(signatureResult.isFailure, isTrue);
      expect(signatureResult.errorOrNull, isA<IdentityError>());
    });
  });

  group('Mock Integration', () {
    test('mocks can be reset between tests', () async {
      final repo = P2PMockRepository();
      final privateKey = Uint8List.fromList(List.generate(32, (i) => i));
      
      await repo.initialize(privateKey, []);
      expect(repo.isInitialized, isTrue);
      
      repo.reset();
      expect(repo.isInitialized, isFalse);
    });

    test('mocks track operation counts', () async {
      final crypto = CryptoMockService();
      final keyPairResult = await crypto.generateEd25519KeyPair();
      expect(keyPairResult.isSuccess, isTrue);
      final keyPair = keyPairResult.valueOrNull!;
      
      expect(crypto.signCallCount, equals(0));
      
      await crypto.sign(
        data: Uint8List.fromList([1, 2, 3]),
        privateKey: keyPair.privateKey,
      );
      await crypto.sign(
        data: Uint8List.fromList([4, 5, 6]),
        privateKey: keyPair.privateKey,
      );
      
      expect(crypto.signCallCount, equals(2));
    });
  });
}

