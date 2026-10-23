import 'package:flutter/foundation.dart';

@immutable
class Paged<T> {
  Paged({
    required List<T> items,
    required this.offset,
    required this.limit,
    this.total,
    this.hasMoreOverride,
  }) : items = List.unmodifiable(items);
  final List<T> items;
  final int offset;
  final int limit;
  final int? total;
  final bool? hasMoreOverride;
  int get nextOffset => offset + items.length;
  bool get hasMore =>
      items.isNotEmpty &&
      (hasMoreOverride ??
          (total != null ? nextOffset < total! : items.length >= limit));
}
