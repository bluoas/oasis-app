import 'package:equatable/equatable.dart';

/// Generic paginated result container
/// 
/// Wraps a list of items with pagination metadata
/// Used for efficient loading of large datasets
/// 
/// Usage:
/// ```dart
/// final result = PaginatedResult(
///   items: [msg1, msg2, msg3],
///   currentPage: 0,
///   pageSize: 50,
///   totalItems: 150,
/// );
/// 
/// if (result.hasMore) {
///   // Load next page
/// }
/// ```
class PaginatedResult<T> extends Equatable {
  /// The items in this page
  final List<T> items;
  
  /// Current page number (0-based)
  final int currentPage;
  
  /// Number of items per page
  final int pageSize;
  
  /// Total number of items across all pages
  final int totalItems;
  
  const PaginatedResult({
    required this.items,
    required this.currentPage,
    required this.pageSize,
    required this.totalItems,
  });
  
  /// Calculate total pages needed
  int get totalPages {
    if (totalItems == 0) return 0;
    return (totalItems / pageSize).ceil();
  }
  
  /// Check if there are more pages to load
  bool get hasMore {
    return currentPage < totalPages - 1;
  }
  
  /// Check if this is the first page
  bool get isFirstPage => currentPage == 0;
  
  /// Check if this is the last page
  bool get isLastPage => !hasMore;
  
  /// Get the index of the first item in this page (0-based)
  int get startIndex => currentPage * pageSize;
  
  /// Get the index of the last item in this page (0-based)
  int get endIndex {
    if (items.isEmpty) return -1;
    return startIndex + items.length - 1;
  }
  
  /// Check if this page is empty
  bool get isEmpty => items.isEmpty;
  
  /// Check if this page has items
  bool get isNotEmpty => items.isNotEmpty;
  
  /// Number of items in current page
  int get itemCount => items.length;
  
  /// Create a copy with updated values
  PaginatedResult<T> copyWith({
    List<T>? items,
    int? currentPage,
    int? pageSize,
    int? totalItems,
  }) {
    return PaginatedResult<T>(
      items: items ?? this.items,
      currentPage: currentPage ?? this.currentPage,
      pageSize: pageSize ?? this.pageSize,
      totalItems: totalItems ?? this.totalItems,
    );
  }
  
  /// Create an empty result
  factory PaginatedResult.empty({int pageSize = 50}) {
    return PaginatedResult<T>(
      items: [],
      currentPage: 0,
      pageSize: pageSize,
      totalItems: 0,
    );
  }
  
  @override
  String toString() {
    return 'PaginatedResult<$T>('
        'page: ${currentPage + 1}/$totalPages, '
        'items: ${items.length}/$totalItems, '
        'hasMore: $hasMore)';
  }
  
  @override
  List<Object?> get props => [items, currentPage, pageSize, totalItems];
}
