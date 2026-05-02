import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/models/message.dart';
import '../mocks/storage_mock_service.dart';

// Helper to create a test message
Message _createMessage(String id, String peerID, String plaintext, DateTime timestamp, {bool fromPeer = true}) {
  return Message(
    id: id,
    senderPeerID: fromPeer ? peerID : 'me',
    targetPeerID: fromPeer ? 'me' : peerID,
    timestamp: timestamp,
    expiresAt: timestamp.add(const Duration(hours: 24)),
    ciphertext: Uint8List.fromList([1, 2, 3]),
    signature: Uint8List.fromList(List.generate(64, (i) => i)),
    nonce: Uint8List.fromList(List.generate(24, (i) => id.hashCode + i)),
    plaintext: plaintext,
    isRead: false,
  );
}

void main() {
  group('StorageService - Pagination', () {
    late StorageMockService storageService;

    setUp(() async {
      storageService = StorageMockService();
      await storageService.initialize();
    });

    test('getMessagesForPeerPaginated returns first page', () async {
      // Create 100 messages
      final peerID = 'peer123';
      final baseTime = DateTime.now();
      final messages = List.generate(100, (i) {
        return _createMessage(
          'msg$i', 
          peerID, 
          'Message $i', 
          baseTime.add(Duration(seconds: i)),
        );
      });

      // Save all messages
      for (final msg in messages) {
        await storageService.saveMessage(msg);
      }

      // Get first page (50 items)
      final result = await storageService.getMessagesForPeerPaginated(
        peerID,
        page: 0,
        pageSize: 50,
      );

      expect(result.isSuccess, true);
      final paginated = result.valueOrNull!;
      
      expect(paginated.items.length, 50);
      expect(paginated.currentPage, 0);
      expect(paginated.pageSize, 50);
      expect(paginated.totalItems, 100);
      expect(paginated.hasMore, true);
      expect(paginated.isFirstPage, true);
      expect(paginated.isLastPage, false);
    });

    test('getMessagesForPeerPaginated returns second page', () async {
      // Create 100 messages
      final peerID = 'peer123';
      final baseTime = DateTime.now();
      final messages = List.generate(100, (i) {
        return _createMessage(
          'msg$i',
          peerID,
          'Message $i',
          baseTime.add(Duration(seconds: i)),
        );
      });

      for (final msg in messages) {
        await storageService.saveMessage(msg);
      }

      // Get second page
      final result = await storageService.getMessagesForPeerPaginated(
        peerID,
        page: 1,
        pageSize: 50,
      );

      expect(result.isSuccess, true);
      final paginated = result.valueOrNull!;
      
      expect(paginated.items.length, 50);
      expect(paginated.currentPage, 1);
      expect(paginated.hasMore, false); // Last page
      expect(paginated.isFirstPage, false);
      expect(paginated.isLastPage, true);
    });

    test('getMessagesForPeerPaginated handles partial last page', () async {
      // Create 75 messages (1.5 pages with pageSize=50)
      final peerID = 'peer123';
      final baseTime = DateTime.now();
      final messages = List.generate(75, (i) {
        return _createMessage(
          'msg$i',
          peerID,
          'Message $i',
          baseTime.add(Duration(seconds: i)),
        );
      });

      for (final msg in messages) {
        await storageService.saveMessage(msg);
      }

      // Get second page (partial)
      final result = await storageService.getMessagesForPeerPaginated(
        peerID,
        page: 1,
        pageSize: 50,
      );

      expect(result.isSuccess, true);
      final paginated = result.valueOrNull!;
      
      expect(paginated.items.length, 25); // Remaining items
      expect(paginated.totalItems, 75);
      expect(paginated.hasMore, false);
    });

    test('getMessagesForPeerPaginated returns empty for page beyond total', () async {
      final peerID = 'peer123';
      final baseTime = DateTime.now();
      
      // Save 10 messages (only 1 page with pageSize=50)
      for (int i = 0; i < 10; i++) {
        await storageService.saveMessage(
          _createMessage(
            'msg$i',
            peerID,
            'Message $i',
            baseTime.add(Duration(seconds: i)),
          ),
        );
      }

      // Request page 5 (beyond available data)
      final result = await storageService.getMessagesForPeerPaginated(
        peerID,
        page: 5,
        pageSize: 50,
      );

      expect(result.isSuccess, true);
      final paginated = result.valueOrNull!;
      
      expect(paginated.items.length, 0);
      expect(paginated.totalItems, 10);
      expect(paginated.hasMore, false);
    });

    test('getMessagesForPeerPaginated works with custom page size', () async {
      final peerID = 'peer123';
      final baseTime = DateTime.now();
      
      // Create 100 messages
      for (int i = 0; i < 100; i++) {
        await storageService.saveMessage(
          _createMessage(
            'msg$i',
            peerID,
            'Message $i',
            baseTime.add(Duration(seconds: i)),
          ),
        );
      }

      // Request with page size 20
      final result = await storageService.getMessagesForPeerPaginated(
        peerID,
        page: 0,
        pageSize: 20,
      );

      expect(result.isSuccess, true);
      final paginated = result.valueOrNull!;
      
      expect(paginated.items.length, 20);
      expect(paginated.pageSize, 20);
      expect(paginated.totalPages, 5); // 100 / 20 = 5 pages
      expect(paginated.hasMore, true);
    });

    test('getMessagesForPeerPaginated filters by peer correctly', () async {
      final peer1 = 'peer1';
      final peer2 = 'peer2';
      final baseTime = DateTime.now();
      
      // Create 50 messages for peer1
      for (int i = 0; i < 50; i++) {
        await storageService.saveMessage(
          Message(
            id: 'peer1_msg$i',
            senderPeerID: peer1,
            targetPeerID: 'me',
            timestamp: baseTime.add(Duration(seconds: i)),
            expiresAt: baseTime.add(Duration(hours: 24, seconds: i)),
            ciphertext: Uint8List.fromList([1, 2, 3]),
            signature: Uint8List.fromList(List.generate(64, (i) => i)),
            nonce: Uint8List.fromList(List.generate(24, (i) => i)),
            plaintext: 'Message $i',
            isRead: false,
          ),
        );
      }

      // Create 30 messages for peer2
      for (int i = 0; i < 30; i++) {
        await storageService.saveMessage(
          Message(
            id: 'peer2_msg$i',
            senderPeerID: peer2,
            targetPeerID: 'me',
            timestamp: baseTime.add(Duration(seconds: i + 100)),
            expiresAt: baseTime.add(Duration(hours: 24, seconds: i + 100)),
            ciphertext: Uint8List.fromList([1, 2, 3]),
            signature: Uint8List.fromList(List.generate(64, (i) => i)),
            nonce: Uint8List.fromList(List.generate(24, (i) => i + 100)),
            plaintext: 'Message $i',
            isRead: false,
          ),
        );
      }

      // Get messages for peer1
      final result1 = await storageService.getMessagesForPeerPaginated(
        peer1,
        page: 0,
        pageSize: 100,
      );

      expect(result1.isSuccess, true);
      final paginated1 = result1.valueOrNull!;
      expect(paginated1.totalItems, 50);
      expect(paginated1.items.every((m) => 
        m.senderPeerID == peer1 || m.targetPeerID == peer1), true);

      // Get messages for peer2
      final result2 = await storageService.getMessagesForPeerPaginated(
        peer2,
        page: 0,
        pageSize: 100,
      );

      expect(result2.isSuccess, true);
      final paginated2 = result2.valueOrNull!;
      expect(paginated2.totalItems, 30);
      expect(paginated2.items.every((m) => 
        m.senderPeerID == peer2 || m.targetPeerID == peer2), true);
    });

    test('getMessagesForPeerPaginated returns empty for unknown peer', () async {
      final result = await storageService.getMessagesForPeerPaginated(
        'unknown_peer',
        page: 0,
        pageSize: 50,
      );

      expect(result.isSuccess, true);
      final paginated = result.valueOrNull!;
      
      expect(paginated.items.length, 0);
      expect(paginated.totalItems, 0);
      expect(paginated.isEmpty, true);
      expect(paginated.hasMore, false);
    });

    test('getMessagesForPeerPaginated validates page parameter', () async {
      final result = await storageService.getMessagesForPeerPaginated(
        'peer123',
        page: -1,
        pageSize: 50,
      );

      expect(result.isFailure, true);
      expect(result.errorOrNull?.message, contains('paginated messages'));
    });

    test('getMessagesForPeerPaginated validates pageSize parameter', () async {
      final result = await storageService.getMessagesForPeerPaginated(
        'peer123',
        page: 0,
        pageSize: 0,
      );

      expect(result.isFailure, true);
      expect(result.errorOrNull?.message, contains('paginated messages'));
    });

    test('getMessagesForPeerPaginated maintains message order', () async {
      final peerID = 'peer123';
      final times = [
        DateTime(2024, 1, 1, 10, 0),
        DateTime(2024, 1, 1, 11, 0),
        DateTime(2024, 1, 1, 12, 0),
        DateTime(2024, 1, 1, 13, 0),
        DateTime(2024, 1, 1, 14, 0),
      ];

      // Save messages in random order
      final messages = [
        _createMessage('msg2', peerID, 'Third', times[2]),
        _createMessage('msg0', peerID, 'First', times[0]),
        _createMessage('msg4', peerID, 'Fifth', times[4]),
      ];

      for (final msg in messages) {
        await storageService.saveMessage(msg);
      }

      // Get paginated messages (should be sorted)
      final result = await storageService.getMessagesForPeerPaginated(
        peerID,
        page: 0,
        pageSize: 50,
      );

      expect(result.isSuccess, true);
      final paginated = result.valueOrNull!;
      
      // Should be sorted by timestamp descending (newest first in getAllMessages, then reversed)
      expect(paginated.items.length, 3);
      // After getAllMessages sorts DESC and ChatScreen reverses, oldest first
      expect(paginated.items[0].plaintext, 'First');
      expect(paginated.items[1].plaintext, 'Third');
      expect(paginated.items[2].plaintext, 'Fifth');
    });
  });
}
