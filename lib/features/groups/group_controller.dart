import 'package:flutter/foundation.dart';
import '../../core/paged.dart';
import '../../core/models.dart';
import '../../domain/models/group_models.dart';
import '../../domain/repositories/group_repository.dart';

@immutable
class ComposeGroupListState {
  ComposeGroupListState({
    List<ComposeGroup> items = const [],
    this.loading = false,
    this.error,
    this.nextOffset = 0,
    this.hasMore = true,
  }) : items = List.unmodifiable(items);
  final List<ComposeGroup> items;
  final bool loading, hasMore;
  final Object? error;
  final int nextOffset;
}

class GroupDirectoryController extends ChangeNotifier {
  GroupDirectoryController(this.repository) {
    repository.sessionChanges.addListener(_sessionChanged);
  }
  final GroupRepository repository;
  String mode = GroupMode.all, sort = GroupSort.updated;
  final Map<(String, String), ComposeGroupListState> _states = {};
  ComposeGroupListState get state =>
      _states[(mode, sort)] ?? ComposeGroupListState();
  int _generation = 0;
  bool _closed = false;
  void _sessionChanged() {
    _states.clear();
    if (!repository.isLoggedIn) mode = GroupMode.all;
    load(reset: true);
  }

  void select({String? mode, String? sort}) {
    this.mode = mode ?? this.mode;
    this.sort = sort ?? this.sort;
    _generation++;
    notifyListeners();
    if (!_states.containsKey((this.mode, this.sort)) || state.loading) {
      load(reset: true);
    }
  }

  Future<void> load({bool reset = false}) async {
    if (!reset && (state.loading || !state.hasMore)) return;
    final key = (mode, sort);
    final previous = state;
    final generation = ++_generation;
    _states[key] = ComposeGroupListState(
      items: previous.items,
      loading: true,
      nextOffset: previous.nextOffset,
      hasMore: previous.hasMore,
    );
    notifyListeners();
    try {
      final Paged<ComposeGroup> page = await repository.list(
        mode: mode,
        sort: sort,
        offset: reset ? 0 : previous.nextOffset,
        fresh: reset,
      );
      if (_closed || generation != _generation) return;
      final byName = {
        for (final item in reset ? <ComposeGroup>[] : previous.items)
          item.name: item,
      };
      for (final item in page.items) {
        byName[item.name] = item;
      }
      _states[key] = ComposeGroupListState(
        items: byName.values.toList(),
        nextOffset: page.nextOffset,
        hasMore: page.hasMore,
      );
    } on Object catch (error) {
      if (_closed || generation != _generation) return;
      _states[key] = ComposeGroupListState(
        items: previous.items,
        error: error,
        nextOffset: previous.nextOffset,
        hasMore: previous.hasMore,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    repository.sessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }
}

@immutable
class ComposeGroupDetailState {
  ComposeGroupDetailState({
    this.group,
    required List<Topic> topics,
    this.loading = false,
    this.loadingDetail = false,
    this.hasMore = true,
    this.error,
    this.detailError,
  }) : topics = List.unmodifiable(topics);
  final ComposeGroup? group;
  final List<Topic> topics;
  final bool loading, loadingDetail, hasMore;
  final Object? error, detailError;
}

class GroupDetailController extends ChangeNotifier {
  GroupDetailController(this.repository, this.name) {
    repository.sessionChanges.addListener(_sessionChanged);
  }
  final GroupRepository repository;
  final String name;
  ComposeGroup? _group;
  final List<Topic> _topics = [];
  bool _loading = false, _loadingDetail = false, _more = true, _closed = false;
  int _offset = 0, _generation = 0;
  Object? _error, _detailError;
  ComposeGroupDetailState get state => ComposeGroupDetailState(
    group: _group,
    topics: _topics,
    loading: _loading,
    loadingDetail: _loadingDetail,
    hasMore: _more,
    error: _error,
    detailError: _detailError,
  );
  void _sessionChanged() {
    _group = null;
    _topics.clear();
    _offset = 0;
    refresh();
  }

  Future<void> refresh() async {
    if (_closed) return;
    final generation = ++_generation;
    _loadingDetail = true;
    _detailError = null;
    await Future.wait([
      _readDetail(generation),
      _readTopics(generation, reset: true),
    ]);
  }

  Future<void> _readDetail(int generation) async {
    try {
      final group = await repository.detail(name);
      if (_closed || generation != _generation) return;
      _group = group;
    } on Object catch (error) {
      if (_closed || generation != _generation) return;
      _detailError = error;
    }
    if (_closed || generation != _generation) return;
    _loadingDetail = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_closed || _loading || _loadingDetail || !_more) return;
    await _readTopics(++_generation, reset: false);
  }

  Future<void> _readTopics(int generation, {required bool reset}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await repository.topics(
        name,
        offset: reset ? 0 : _offset,
        fresh: reset,
      );
      if (_closed || generation != _generation) return;
      if (reset) _topics.clear();
      final ids = _topics.map((e) => e.id).toSet();
      _topics.addAll(page.items.where((e) => ids.add(e.id)));
      _offset = page.nextOffset;
      _more = page.hasMore;
    } on Object catch (error) {
      if (_closed || generation != _generation) return;
      _error = error;
    }
    if (_closed || generation != _generation) return;
    _loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    repository.sessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }
}
