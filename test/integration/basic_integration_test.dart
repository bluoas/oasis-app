import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'dart:convert';

import '../../lib/models/message.dart';
import '../../lib/models/contact.dart';
import '../mocks/crypto_mock_service.dart';
import '../mocks/identity_mock_service.dart';
import '../mocks/storage_mock_service.dart';

/// Basic Integration Tests
/// 
/// Tests that verify the interaction between storage, crypto, and identity services
void main() {
  group('Basic Integration Tests', () {
    late CryptoMockService mockCrypto;
    late IdentityMockService mockIdentity;
    late StorageMockService mockStorage;

    setUp(() async {
      mockCrypto = CryptoMockService();
      mockIdentity = IdentityMockService(crypto: mockCrypto);
      mockStorage = StorageMockService();

      await mockStorage.initialize();
      await mockIdentity.initialize();
    });

    test('Identity creation and signing', () async {
      // Create identity
      await mockIdentity.createTestIdentity();
      expect(mockIdentity.peerID, isNotEmpty);
      expect(mockIdentity.privateKey!.length, 32);
      expect(mockIdentity.publicKey!.length, 32);

      // Sign data
      final data = utf8.encode('Test message');
      final signResult = await mockIdentity.sign(data);
      expect(signResult.isSuccess, true);
      expect(signResult.value.length, 64);

      // Verify signature
      final verifyResult = await mockIdentity.verify(
        data: data,
        signature: signResult.value,
        publicKey: mockIdentity.publicKey!,
      );
      expect(verifyResult.isSuccess, true);
      expect(verifyResult.value, true);
    });

    test('Crypto encrypt and decrypt', () async {
      // Generate two keypairs
      final aliceKeys = await mockCrypto.generateEd25519KeyPair();
      final bobKeys = await mockCrypto.generateEd25519KeyPair();
      
      expect(aliceKeys.isSuccess, true);
      expect(bobKeys.isSuccess, true);

      // Alice encrypts for Bob
      final plaintext = 'Secret message';
      final encryptResult = await mockCrypto.encrypt(
        plaintext: plaintext,
        senderPrivateKey: aliceKeys.value.privateKey,
        recipientPublicKey: bobKeys.value.publicKey,
      );
      expect(encryptResult.isSuccess, true);

      // Bob decrypts
      final decryptResult = await mockCrypto.decrypt(
        ciphertext: encryptResult.value,
        recipientPrivateKey: bobKeys.value.privateKey,
        senderPublicKey: aliceKeys.value.publicKey,
      );
      expect(decryptResult.isSuccess, true);
      expect(decryptResult.value, plaintext);
    });

    test('Storage: Save and retrieve contact', () async {
      final contact = Contact(
        peerID: 'test-peer-id',
        displayName: 'Alice',
        userName: 'Alice',
        addedAt: DateTime.now(),
      );

      // Save
      final saveResult = await mockStorage.saveContact(contact);
      expect(saveResult.isSuccess, true);

      // Retrieve
      final getResult = await mockStorage.getContact(contact.peerID);
      expect(getResult.isSuccess, true);
      expect(getResult.value!.peerID, contact.peerID);
      expect(getResult.value!.displayName, 'Alice');
    });

    test('Storage: Save and retrieve message', () async {
      final now = DateTime.now();
      final message = Message(
        id: 'test-msg-1',
        senderPeerID: 'sender-123',
        targetPeerID: 'target-456',
        timestamp: now,
        expiresAt: now.add(const Duration(hours: 24)),
        ciphertext: utf8.encode('encrypted'),
        signature: Uint8List(64),
        nonce: Uint8List(24),
        plaintext: 'Hello',
      );

      // Save
      final saveResult = await mockStorage.saveMessage(message);
      expect(saveResult.isSuccess, true);

      // Retrieve
      final getResult = await mockStorage.getMessage(message.id);
      expect(getResult.isSuccess, true);
      expect(getResult.value!.id, message.id);
      expect(getResult.value!.plaintext, 'Hello');
    });

    test('Storage: Get messages for peer', () async {
      final peerID = 'peer-123';
      final now = DateTime.now();

      // Save contact
      await mockStorage.saveContact(Contact(
        peerID: peerID,
        displayName: 'Alice',
        userName: 'Alice',
        addedAt: now,
      ));

      // Save messages
      for (var i = 0; i < 3; i++) {
        await mockStorage.saveMessage(Message(
          id: 'msg-$i',
          senderPeerID: peerID,
          targetPeerID: 'me',
          timestamp: now.add(Duration(minutes: i)),
          expiresAt: now.add(Duration(hours: 24 + i)),
          ciphertext: utf8.encode('test'),
          signature: Uint8List(64),
          nonce: Uint8List(24),
          plaintext: 'Message $i',
        ));
      }

      // Retrieve messages for peer
      final result = await mockStorage.getMessagesForPeer(peerID);
      expect(result.isSuccess, true);
      expect(result.value.length, 3);
      expect(result.value[0].plaintext, 'Message 0');
      expect(result.value[1].plaintext, 'Message 1');
      expect(result.value[2].plaintext, 'Message 2');
    });

    test('Nonce replay protection', () async {
      final nonce = 'test-nonce';

      // First check - should be new
      final firstCheck = await mockStorage.hasSeenNonce(nonce);
      expect(firstCheck.value, false);

      // Mark as seen
      await mockStorage.markNonceSeen(nonce);

      // Second check - should be seen
      final secondCheck = await mockStorage.hasSeenNonce(nonce);
      expect(secondCheck.value, true);
    });

    test('Clear all storage', () async {
      // Add data
      await mockStorage.saveContact(Contact(
        peerID: 'peer-1',
        displayName: 'Alice',
        userName: 'Alice',
        addedAt: DateTime.now(),
      ));

      final now = DateTime.now();
      await mockStorage.saveMessage(Message(
        id: 'msg-1',
        senderPeerID: 'peer-1',
        targetPeerID: 'me',
        timestamp: now,
        expiresAt: now.add(const Duration(hours: 24)),
        ciphertext: utf8.encode('test'),
        signature: Uint8List(64),
        nonce: Uint8List(24),
      ));

      // Clear all
      final clearResult = await mockStorage.clearAll();
      expect(clearResult.isSuccess, true);

      // Verify cleared
      final contacts = await mockStorage.getAllContacts();
      expect(contacts.value.length, 0);
    });

    test('Full encryption workflow', () async {
      // Setup Alice and Bob
      await mockIdentity.createTestIdentity();
      final bobKeys = await mockCrypto.generateEd25519KeyPair();
      expect(bobKeys.isSuccess, true);

      // Alice encrypts message for Bob
      final plaintext = 'Hello Bob!';
      final encryptResult = await mockCrypto.encrypt(
        plaintext: plaintext,
        senderPrivateKey: mockIdentity.privateKey!,
        recipientPublicKey: bobKeys.value.publicKey,
      );
      expect(encryptResult.isSuccess,true);

      // Create and save message
      final now = DateTime.now();
      final message = Message(
        id: 'msg-1',
        senderPeerID: mockIdentity.peerID!,
        targetPeerID: 'bob-peer-id',
        timestamp: now,
        expiresAt: now.add(const Duration(hours: 24)),
        ciphertext: encryptResult.value,
        signature: Uint8List(64),
        nonce: Uint8List(24),
        senderPublicKey: mockIdentity.publicKey!,
      );

      await mockStorage.saveMessage(message);

      // Bob retrieves and decrypts
      final retrieved = await mockStorage.getMessage(message.id);
      expect(retrieved.isSuccess, true);

      final decryptResult = await mockCrypto.decrypt(
        ciphertext: retrieved.value!.ciphertext,
        recipientPrivateKey: bobKeys.value.privateKey,
        senderPublicKey: mockIdentity.publicKey!,
      );
      expect(decryptResult.isSuccess, true);
      expect(decryptResult.value, plaintext);
    });

    test('Identity reset clears everything', () async {
      // Create identity and data
      await mockIdentity.createTestIdentity();
      expect(mockIdentity.peerID, isNotNull);

      await mockStorage.saveContact(Contact(
        peerID: 'peer-1',
        displayName: 'Alice',
        userName: 'Alice',
        addedAt: DateTime.now(),
      ));

      // Reset identity
      await mockIdentity.deleteIdentity();
      expect(mockIdentity.peerID, isNull);

      // Clear storage
      await mockStorage.clearAll();
      final contacts = await mockStorage.getAllContacts();
      expect(contacts.value.length, 0);

      // Create new identity
      await mockIdentity.createTestIdentity('new');
      expect(mockIdentity.peerID, isNotEmpty);
    });
  });
}
