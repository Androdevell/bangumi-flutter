import 'package:flutter/foundation.dart';
import 'paged.dart';
import 'network/read_task_scope.dart';

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
  final Set<Object> _ids = {};
  List<T>? _snapshot;
  List<T> get items => _snapshot ??= List.unmodifiable(_items);
  bool loading = false;
  bool hasMore = true;
  Object? error;
  int? total;
  int _cursor = 0;
  int _generation = 0;
  bool _disposed = false;
  ReadTaskScope _read = ReadTaskScope();

  Future<void> reset({bool keepItems = false}) {
    _read.cancel();
    _read = ReadTaskScope();
    _generation++;
    _cursor = 0;
    loading = false;
    hasMore = true;
    error = null;
    total = null;
    if (!keepItems) {
      _items.clear();
      _ids.clear();
      _snapshot = null;
    }
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
      final page = await _read.run(() => load(cursor));
      if (_disposed || generation != _generation) return;
      if (cursor == 0) {
        _items.clear();
        _ids.clear();
      }
      final fresh = page.items.where((item) => _ids.add(idOf(item))).toList();
      _items.addAll(fresh);
      _snapshot = null;
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
    _read.cancel();
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
