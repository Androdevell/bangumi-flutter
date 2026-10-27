import 'package:flutter/foundation.dart';
import '../../../domain/models/cache_usage.dart';

@immutable
class ComposeCacheState {
  ComposeCacheState({
    Iterable<ComposeCacheUsage> usage = const [],
    Iterable<CacheCategory> selected = const [
      CacheCategory.images,
      CacheCategory.publicData,
      CacheCategory.memory,
      CacheCategory.temporary,
    ],
    this.loading = false,
    this.clearing = false,
    this.result,
    this.failed = false,
  }) : usage = List.unmodifiable(usage),
       selected = Set.unmodifiable(selected);
  final List<ComposeCacheUsage> usage;
  final Set<CacheCategory> selected;
  final bool loading, clearing, failed;
  final ComposeCacheClearResult? result;
}

sealed class CacheIntent {
  const CacheIntent();
}

class LoadCacheUsage extends CacheIntent {
  const LoadCacheUsage();
}

class SelectCacheCategory extends CacheIntent {
  const SelectCacheCategory(this.category, this.selected);
  final CacheCategory category;
  final bool selected;
}

class CacheController extends ChangeNotifier {
  CacheController(this.service);
  final CacheMaintenance service;
  ComposeCacheState state = ComposeCacheState();
  bool _disposed = false;
  void _emit(ComposeCacheState next) {
    if (!_disposed) {
      state = next;
      notifyListeners();
    }
  }

  Future<void> dispatch(CacheIntent intent) async {
    if (_disposed || state.clearing || state.loading) return;
    if (intent is SelectCacheCategory) {
      final selected = {...state.selected};
      intent.selected
          ? selected.add(intent.category)
          : selected.remove(intent.category);
      _emit(ComposeCacheState(usage: state.usage, selected: selected));
    } else if (intent is LoadCacheUsage) {
      await _refresh();
    }
  }

  Future<void> _refresh({ComposeCacheClearResult? result}) async {
    _emit(
      ComposeCacheState(
        usage: state.usage,
        selected: state.selected,
        loading: true,
        result: result,
      ),
    );
    try {
      final usage = await service.scan();
      _emit(
        ComposeCacheState(
          usage: usage,
          selected: state.selected.where(
            (category) => usage.any(
              (item) => item.category == category && !item.unavailable,
            ),
          ),
          result: result,
        ),
      );
    } catch (_) {
      _emit(
        ComposeCacheState(
          usage: state.usage,
          selected: state.selected,
          failed: true,
          result: result,
        ),
      );
    }
  }

  Future<void> clear(Set<CacheCategory> categories) async {
    if (_disposed || state.loading || state.clearing || categories.isEmpty) {
      return;
    }
    final selected = Set<CacheCategory>.unmodifiable(categories);
    _emit(
      ComposeCacheState(
        usage: state.usage,
        selected: state.selected,
        clearing: true,
      ),
    );
    ComposeCacheClearResult result;
    try {
      result = await service.clear(selected);
    } catch (_) {
      result = ComposeCacheClearResult(failed: selected);
    }
    if (!_disposed) await _refresh(result: result);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
