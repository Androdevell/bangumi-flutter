import 'package:flutter/foundation.dart';
import 'paged.dart';

class PagedController<T> extends ChangeNotifier {
  PagedController({
    required this.load,
    required this.idOf,
    this.pageBased = false,
  });
  final Future<Paged<T>> Function(int cursor) load;
  final Object Function(T item) idOf;
  final bool pageBased;
  final List<T> _items = [];
  List<T> get items => List.unmodifiable(_items);
  bool loading = false;
  bool hasMore = true;
  Object? error;
  int? total;
  int _cursor = 0;
  int _generation = 0;
  bool _disposed = false;

  Future<void> reset({bool keepItems = false}) {
    _generation++;
    _cursor = 0;
    loading = false;
    hasMore = true;
    error = null;
    total = null;
    if (!keepItems) _items.clear();
    return loadMore();
  }

  Future<void> loadMore() async {
    if (_disposed || loading || !hasMore) return;
    final generation = _generation;
    final cursor = _cursor;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await load(cursor);
      if (_disposed || generation != _generation) return;
      if (cursor == 0) _items.clear();
      final ids = _items.map(idOf).toSet();
      final fresh = page.items.where((item) => ids.add(idOf(item))).toList();
      _items.addAll(fresh);
      total = page.total;
      hasMore = page.hasMore && fresh.isNotEmpty;
      _cursor = pageBased ? cursor + 1 : page.nextOffset;
      if (!pageBased && _cursor <= cursor) hasMore = false;
    } on Object catch (failure) {
      if (!_disposed && generation == _generation) error = failure;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
