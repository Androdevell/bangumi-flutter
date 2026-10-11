import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/community_models.dart';
import '../../core/paged.dart';
import '../../domain/models/collection_models.dart';

@immutable
sealed class CollectionIntent {
  const CollectionIntent();
}

final class LoadCollections extends CollectionIntent {
  const LoadCollections({this.refresh = false});
  final bool refresh;
}

final class ChangeCollectionFilter extends CollectionIntent {
  const ChangeCollectionFilter(this.query);
  final CollectionQuery query;
}

@immutable
class ComposeCollectionState {
  ComposeCollectionState({
    required this.query,
    List<UserContentItem> items = const [],
    this.loading = false,
    this.hasMore = true,
    this.offset = 0,
    this.total,
    this.error,
  }) : items = List.unmodifiable(items);

  final CollectionQuery query;
  final List<UserContentItem> items;
  final bool loading;
  final bool hasMore;
  final int offset;
  final int? total;
  final Object? error;
}

@immutable
sealed class CollectionAction {
  const CollectionAction();
}

final class CollectionLoading extends CollectionAction {
  const CollectionLoading(this.offset);
  final int offset;
}

final class CollectionLoaded extends CollectionAction {
  const CollectionLoaded(this.page);
  final Paged<UserContentItem> page;
}

final class CollectionFailed extends CollectionAction {
  const CollectionFailed(this.error);
  final Object error;
}

/// 纯状态归约：不请求网络、不访问时钟、不执行 UI 副作用。
ComposeCollectionState reduceCollection(
  ComposeCollectionState state,
  CollectionAction action,
) => switch (action) {
  CollectionLoading(:final offset) => ComposeCollectionState(
    query: state.query,
    items: state.items,
    loading: true,
    hasMore: offset == 0 || state.hasMore,
    offset: offset,
    total: state.total,
  ),
  CollectionLoaded(:final page) => _mergePage(state, page),
  CollectionFailed(:final error) => ComposeCollectionState(
    query: state.query,
    items: state.items,
    offset: state.offset,
    total: state.total,
    hasMore: state.hasMore,
    error: error,
  ),
};

ComposeCollectionState _mergePage(
  ComposeCollectionState state,
  Paged<UserContentItem> page,
) {
  final items = page.offset == 0 ? <UserContentItem>[] : state.items.toList();
  final ids = items.map((item) => item.id).toSet();
  items.addAll(page.items.where((item) => ids.add(item.id)));
  return ComposeCollectionState(
    query: state.query,
    items: items,
    total: page.total,
    offset: page.nextOffset,
    hasMore: page.hasMore && page.nextOffset > page.offset,
  );
}

class CollectionController extends ChangeNotifier {
  CollectionController({required CollectionQuery query, required this.load})
    : _state = ComposeCollectionState(query: query);

  final Future<Paged<UserContentItem>> Function(
    CollectionQuery query,
    int offset,
    bool fresh,
  )
  load;
  ComposeCollectionState _state;
  ComposeCollectionState get state => _state;
  int _generation = 0;
  bool _disposed = false;

  Future<void> dispatch(CollectionIntent intent) async {
    if (_disposed) return;
    if (intent is ChangeCollectionFilter) {
      _generation++;
      _state = ComposeCollectionState(query: intent.query);
      await _load(fresh: false);
    } else if (intent is LoadCollections) {
      if (intent.refresh) {
        _generation++;
        await _load(fresh: true, reset: true);
      } else {
        await _load(fresh: false);
      }
    }
  }

  Future<void> _load({required bool fresh, bool reset = false}) async {
    if (!reset && (_state.loading || !_state.hasMore)) return;
    final generation = _generation;
    final query = _state.query;
    final offset = reset ? 0 : _state.offset;
    _state = reduceCollection(_state, CollectionLoading(offset));
    notifyListeners();
    try {
      final page = await load(query, offset, fresh);
      if (_disposed || generation != _generation) return;
      _state = reduceCollection(_state, CollectionLoaded(page));
    } on Object catch (error) {
      if (_disposed || generation != _generation) return;
      _state = reduceCollection(_state, CollectionFailed(error));
    }
    notifyListeners();
  }

  void clearSession() {
    if (_disposed) return;
    _generation++;
    _state = ComposeCollectionState(query: _state.query);
    notifyListeners();
    unawaited(dispatch(const LoadCollections(refresh: true)));
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
