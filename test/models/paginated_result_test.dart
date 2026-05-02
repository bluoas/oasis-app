import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/models/paginated_result.dart';
import '../../lib/models/message.dart';

void main() {
  group('PaginatedResult', () {
    test('creates with valid data', () {
      final result = PaginatedResult<String>(
        items: ['a', 'b', 'c'],
        currentPage: 0,
        pageSize: 10,
        totalItems: 25,
      );

      expect(result.items, ['a', 'b', 'c']);
      expect(result.currentPage, 0);
      expect(result.pageSize, 10);
      expect(result.totalItems, 25);
    });

    test('calculates totalPages correctly', () {
      // 25 items with page size 10 = 3 pages
      final result1 = PaginatedResult<String>(
        items: [],
        currentPage: 0,
        pageSize: 10,
        totalItems: 25,
      );
      expect(result1.totalPages, 3);

      // 30 items with page size 10 = 3 pages (exact)
      final result2 = PaginatedResult<String>(
        items: [],
        currentPage: 0,
        pageSize: 10,
        totalItems: 30,
      );
      expect(result2.totalPages, 3);

      // 0 items = 0 pages
      final result3 = PaginatedResult<String>(
        items: [],
        currentPage: 0,
        pageSize: 10,
        totalItems: 0,
      );
      expect(result3.totalPages, 0);
    });

    test('calculates hasMore correctly', () {
      // Page 0 of 3 pages = has more
      final result1 = PaginatedResult<String>(
        items: [],
        currentPage: 0,
        pageSize: 10,
        totalItems: 25,
      );
      expect(result1.hasMore, true);

      // Page 1 of 3 pages = has more
      final result2 = PaginatedResult<String>(
        items: [],
        currentPage: 1,
        pageSize: 10,
        totalItems: 25,
      );
      expect(result2.hasMore, true);

      // Last page (page 2 of 3) = no more
      final result3 = PaginatedResult<String>(
        items: [],
        currentPage: 2,
        pageSize: 10,
        totalItems: 25,
      );
      expect(result3.hasMore, false);

      // Single page = no more
      final result4 = PaginatedResult<String>(
        items: [],
        currentPage: 0,
        pageSize: 10,
        totalItems: 5,
      );
      expect(result4.hasMore, false);
    });

    test('isFirstPage returns correct value', () {
      final result1 = PaginatedResult<String>(
        items: [],
        currentPage: 0,
        pageSize: 10,
        totalItems: 25,
      );
      expect(result1.isFirstPage, true);

      final result2 = PaginatedResult<String>(
        items: [],
        currentPage: 1,
        pageSize: 10,
        totalItems: 25,
      );
      expect(result2.isFirstPage, false);
    });

    test('isLastPage returns correct value', () {
      final result1 = PaginatedResult<String>(
        items: [],
        currentPage: 2,
        pageSize: 10,
        totalItems: 25,
      );
      expect(result1.isLastPage, true);

      final result2 = PaginatedResult<String>(
        items: [],
        currentPage: 1,
        pageSize: 10,
        totalItems: 25,
      );
      expect(result2.isLastPage, false);
    });

    test('calculates startIndex and endIndex correctly', () {
      // Page 0: items 0-9
      final result1 = PaginatedResult<String>(
        items: List.generate(10, (i) => 'item$i'),
        currentPage: 0,
        pageSize: 10,
        totalItems: 25,
      );
      expect(result1.startIndex, 0);
      expect(result1.endIndex, 9);

      // Page 1: items 10-19
      final result2 = PaginatedResult<String>(
        items: List.generate(10, (i) => 'item${i + 10}'),
        currentPage: 1,
        pageSize: 10,
        totalItems: 25,
      );
      expect(result2.startIndex, 10);
      expect(result2.endIndex, 19);

      // Last page (partial): items 20-24
      final result3 = PaginatedResult<String>(
        items: List.generate(5, (i) => 'item${i + 20}'),
        currentPage: 2,
        pageSize: 10,
        totalItems: 25,
      );
      expect(result3.startIndex, 20);
      expect(result3.endIndex, 24);

      // Empty page
      final result4 = PaginatedResult<String>(
        items: [],
        currentPage: 3,
        pageSize: 10,
        totalItems: 25,
      );
      expect(result4.startIndex, 30);
      expect(result4.endIndex, -1); // No items
    });

    test('isEmpty returns correct value', () {
      final result1 = PaginatedResult<String>(
        items: [],
        currentPage: 0,
        pageSize: 10,
        totalItems: 0,
      );
      expect(result1.isEmpty, true);

      final result2 = PaginatedResult<String>(
        items: ['a'],
        currentPage: 0,
        pageSize: 10,
        totalItems: 1,
      );
      expect(result2.isEmpty, false);
    });

    test('copyWith creates modified copy', () {
      final original = PaginatedResult<String>(
        items: ['a', 'b'],
        currentPage: 0,
        pageSize: 10,
        totalItems: 25,
      );

      final modified = original.copyWith(
        currentPage: 1,
        items: ['c', 'd'],
      );

      expect(modified.currentPage, 1);
      expect(modified.items, ['c', 'd']);
      expect(modified.pageSize, 10); // Unchanged
      expect(modified.totalItems, 25); // Unchanged

      // Original unchanged
      expect(original.currentPage, 0);
      expect(original.items, ['a', 'b']);
    });

    test('empty factory creates empty result', () {
      final result = PaginatedResult<String>.empty();

      expect(result.items, []);
      expect(result.currentPage, 0);
      expect(result.pageSize, 50); // Default
      expect(result.totalItems, 0);
      expect(result.isEmpty, true);
      expect(result.hasMore, false);
    });

    test('empty factory accepts custom pageSize', () {
      final result = PaginatedResult<String>.empty(pageSize: 25);

      expect(result.pageSize, 25);
    });

    test('toString returns readable representation', () {
      final result = PaginatedResult<String>(
        items: ['a', 'b', 'c'],
        currentPage: 1,
        pageSize: 10,
        totalItems: 25,
      );

      final str = result.toString();
      expect(str, contains('PaginatedResult'));
      expect(str, contains('page: 2/3')); // currentPage 1 = "page 2" in 1-based display
      expect(str, contains('items: 3/25'));
      expect(str, contains('hasMore: true'));
    });

    test('equality works correctly', () {
      final result1 = PaginatedResult<String>(
        items: ['a', 'b'],
        currentPage: 0,
        pageSize: 10,
        totalItems: 25,
      );

      final result2 = PaginatedResult<String>(
        items: ['a', 'b'],
        currentPage: 0,
        pageSize: 10,
        totalItems: 25,
      );

      final result3 = PaginatedResult<String>(
        items: ['c', 'd'],
        currentPage: 0,
        pageSize: 10,
        totalItems: 25,
      );

      expect(result1 == result2, true);
      expect(result1 == result3, false);
      expect(result1.hashCode == result2.hashCode, true);
    });

    test('works with different types', () {
      // Test with Message model
      final now = DateTime.now();
      final messages = [
        Message(
          id: '1',
          senderPeerID: 'peer1',
          targetPeerID: 'peer2',
          timestamp: now,
          expiresAt: now.add(const Duration(hours: 24)),
          ciphertext: Uint8List.fromList([1, 2, 3]),
          signature: Uint8List.fromList(List.generate(64, (i) => i)),
          nonce: Uint8List.fromList(List.generate(24, (i) => i)),
          plaintext: 'Hello',
          isRead: false,
        ),
      ];

      final result = PaginatedResult<Message>(
        items: messages,
        currentPage: 0,
        pageSize: 50,
        totalItems: 1,
      );

      expect(result.items.length, 1);
      expect(result.items.first.plaintext, 'Hello');
    });
  });
}
