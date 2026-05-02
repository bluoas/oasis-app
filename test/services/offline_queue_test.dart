import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/models/message.dart';
import 'dart:typed_data';
import 'dart:convert';

void main() {
  group('DeliveryStatus Enum Tests', () {
    test('DeliveryStatus.pending serializes to "pending"', () {
      expect(DeliveryStatus.pending.toJson(), equals('pending'));
    });

    test('DeliveryStatus.sent serializes to "sent"', () {
      expect(DeliveryStatus.sent.toJson(), equals('sent'));
    });

    test('DeliveryStatus.delivered serializes to "delivered"', () {
      expect(DeliveryStatus.delivered.toJson(), equals('delivered'));
    });

    test('DeliveryStatus.failed serializes to "failed"', () {
      expect(DeliveryStatus.failed.toJson(), equals('failed'));
    });

    test('DeliveryStatus deserializes "pending" correctly', () {
      expect(DeliveryStatus.fromJson('pending'), equals(DeliveryStatus.pending));
    });

    test('DeliveryStatus deserializes "sent" correctly', () {
      expect(DeliveryStatus.fromJson('sent'), equals(DeliveryStatus.sent));
    });

    test('DeliveryStatus deserializes "failed" correctly', () {
      expect(DeliveryStatus.fromJson('failed'), equals(DeliveryStatus.failed));
    });

    test('DeliveryStatus deserializes invalid value to "pending" (fallback)', () {
      expect(DeliveryStatus.fromJson('invalid'), equals(DeliveryStatus.pending));
    });
  });

  group('Message Model with DeliveryStatus Tests', () {
    final testMessage = Message(
      id: 'test-id-123',
      senderPeerID: 'sender-peer-id',
      targetPeerID: 'target-peer-id',
      timestamp: DateTime.utc(2026, 3, 20, 12, 0),
      expiresAt: DateTime.utc(2026, 3, 21, 12, 0),
      ciphertext: Uint8List.fromList([1, 2, 3]),
      signature: Uint8List.fromList([4, 5, 6]),
      nonce: Uint8List.fromList([7, 8, 9]),
      senderPublicKey: Uint8List.fromList([10, 11, 12]),
      plaintext: 'Hello World',
      deliveryStatus: DeliveryStatus.pending,
    );

    test('Message created with pending status', () {
      expect(testMessage.deliveryStatus, equals(DeliveryStatus.pending));
    });

    test('Message defaults to sent status when not specified', () {
      final defaultMessage = Message(
        id: 'test-id-456',
        senderPeerID: 'sender-peer-id',
        targetPeerID: 'target-peer-id',
        timestamp: DateTime.utc(2026, 3, 20, 12, 0),
        expiresAt: DateTime.utc(2026, 3, 21, 12, 0),
        ciphertext: Uint8List.fromList([1, 2, 3]),
        signature: Uint8List.fromList([4, 5, 6]),
        nonce: Uint8List.fromList([7, 8, 9]),
        senderPublicKey: Uint8List.fromList([10, 11, 12]),
      );

      expect(defaultMessage.deliveryStatus, equals(DeliveryStatus.sent));
    });

    test('Message copyWith updates deliveryStatus', () {
      final updatedMessage = testMessage.copyWith(
        deliveryStatus: DeliveryStatus.sent,
      );

      expect(updatedMessage.deliveryStatus, equals(DeliveryStatus.sent));
      expect(updatedMessage.id, equals(testMessage.id));
    });

    test('Message copyWith preserves other fields', () {
      final updatedMessage = testMessage.copyWith(
        deliveryStatus: DeliveryStatus.failed,
      );

      expect(updatedMessage.id, equals(testMessage.id));
      expect(updatedMessage.senderPeerID, equals(testMessage.senderPeerID));
      expect(updatedMessage.targetPeerID, equals(testMessage.targetPeerID));
      expect(updatedMessage.plaintext, equals(testMessage.plaintext));
    });

    test('Message toLocalJson includes deliveryStatus', () {
      final json = testMessage.toLocalJson();

      expect(json['deliveryStatus'], equals('pending'));
    });

    test('Message fromLocalJson deserializes deliveryStatus', () {
      final json = {
        'id': 'test-id-789',
        'sender_peer_id': 'sender-peer-id',
        'target_peer_id': 'target-peer-id',
        'timestamp': '2026-03-20T12:00:00.000Z',
        'expires_at': '2026-03-21T12:00:00.000Z',
        'ciphertext': base64.encode([1, 2, 3]),
        'signature': base64.encode([4, 5, 6]),
        'nonce': base64.encode([7, 8, 9]),
        'sender_public_key': base64.encode([10, 11, 12]),
        'plaintext': 'Test',
        'isRead': false,
        'deliveryStatus': 'failed',
      };

      final message = Message.fromLocalJson(json);

      expect(message.deliveryStatus, equals(DeliveryStatus.failed));
    });

    test('Message fromLocalJson handles missing deliveryStatus (backward compatibility)', () {
      final json = {
        'id': 'test-id-999',
        'sender_peer_id': 'sender-peer-id',
        'target_peer_id': 'target-peer-id',
        'timestamp': '2026-03-20T12:00:00.000Z',
        'expires_at': '2026-03-21T12:00:00.000Z',
        'ciphertext': base64.encode([1, 2, 3]),
        'signature': base64.encode([4, 5, 6]),
        'nonce': base64.encode([7, 8, 9]),
        'sender_public_key': base64.encode([10, 11, 12]),
        'plaintext': 'Test',
        'isRead': false,
        // deliveryStatus missing (old messages)
      };

      final message = Message.fromLocalJson(json);

      // Should default to sent for backward compatibility
      expect(message.deliveryStatus, equals(DeliveryStatus.sent));
    });
  });

  group('Offline Queue Logic Tests', () {
    test('Message transitions from pending to sent', () {
      final pendingMessage = Message(
        id: 'test-id',
        senderPeerID: 'sender',
        targetPeerID: 'target',
        timestamp: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        ciphertext: Uint8List.fromList([1, 2, 3]),
        signature: Uint8List.fromList([4, 5, 6]),
        nonce: Uint8List.fromList([7, 8, 9]),
        senderPublicKey: Uint8List.fromList([10, 11, 12]),
        deliveryStatus: DeliveryStatus.pending,
      );

      expect(pendingMessage.deliveryStatus, equals(DeliveryStatus.pending));

      final sentMessage = pendingMessage.copyWith(
        deliveryStatus: DeliveryStatus.sent,
      );

      expect(sentMessage.deliveryStatus, equals(DeliveryStatus.sent));
    });

    test('Message transitions from pending to failed on error', () {
      final pendingMessage = Message(
        id: 'test-id',
        senderPeerID: 'sender',
        targetPeerID: 'target',
        timestamp: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        ciphertext: Uint8List.fromList([1, 2, 3]),
        signature: Uint8List.fromList([4, 5, 6]),
        nonce: Uint8List.fromList([7, 8, 9]),
        senderPublicKey: Uint8List.fromList([10, 11, 12]),
        deliveryStatus: DeliveryStatus.pending,
      );

      final failedMessage = pendingMessage.copyWith(
        deliveryStatus: DeliveryStatus.failed,
      );

      expect(failedMessage.deliveryStatus, equals(DeliveryStatus.failed));
    });

    test('Failed message can be retried (back to pending)', () {
      final failedMessage = Message(
        id: 'test-id',
        senderPeerID: 'sender',
        targetPeerID: 'target',
        timestamp: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        ciphertext: Uint8List.fromList([1, 2, 3]),
        signature: Uint8List.fromList([4, 5, 6]),
        nonce: Uint8List.fromList([7, 8, 9]),
        senderPublicKey: Uint8List.fromList([10, 11, 12]),
        deliveryStatus: DeliveryStatus.failed,
      );

      final retryMessage = failedMessage.copyWith(
        deliveryStatus: DeliveryStatus.pending,
      );

      expect(retryMessage.deliveryStatus, equals(DeliveryStatus.pending));
    });
  });
}
