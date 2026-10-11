import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/models.dart';
import '../../data/bangumi_repository.dart';

@immutable
class ComposeDiscoverState {
  const ComposeDiscoverState({
    this.calendar,
    this.loading = false,
    this.cached = false,
    this.updatedAt,
    this.error,
  });
  final Map<String, List<Subject>>? calendar;
  final bool loading;
  final bool cached;
  final DateTime? updatedAt;
  final Object? error;
}

sealed class DiscoverIntent {}

class LoadDiscover extends DiscoverIntent {}

class RefreshDiscover extends DiscoverIntent {}

class DiscoverController extends ChangeNotifier {
  DiscoverController(this.repository);
  final BangumiRepository repository;
  ComposeDiscoverState state = const ComposeDiscoverState();
  bool _closed = false;
  bool _fresh = false;
  int _generation = 0;
  void dispatch(DiscoverIntent intent) {
    if (_closed || state.loading) return;
    if (intent is LoadDiscover && repository is CalendarSnapshotRepository) {
      unawaited(_readSnapshot());
    }
    unawaited(refresh(force: intent is RefreshDiscover));
  }

  Future<void> _readSnapshot() async {
    try {
      final snapshot =
          await (repository as CalendarSnapshotRepository)
              .readCalendarSnapshot();
      if (!_closed && !_fresh && snapshot != null) {
        state = ComposeDiscoverState(
          calendar: snapshot.calendar,
          cached: true,
          loading: state.loading,
          updatedAt: snapshot.savedAt,
          error: state.error,
        );
        notifyListeners();
      }
    } on Object {
      // 缓存损坏或读取失败不影响同时进行的网络刷新。
    }
  }

  Future<void> refresh({bool force = true}) async {
    if (_closed || state.loading) return;
    final generation = ++_generation;
    state = ComposeDiscoverState(
      calendar: state.calendar,
      loading: true,
      cached: state.cached,
      updatedAt: state.updatedAt,
    );
    notifyListeners();
    try {
      final result =
          force && repository is CalendarSnapshotRepository
              ? await (repository as CalendarSnapshotRepository)
                  .refreshCalendar()
              : await repository.fetchCalendar();
      if (_closed || generation != _generation) return;
      _fresh = true;
      state = ComposeDiscoverState(
        calendar: Map.unmodifiable(
          result.map(
            (key, value) => MapEntry(key, List<Subject>.unmodifiable(value)),
          ),
        ),
        updatedAt: DateTime.now(),
      );
    } on Object catch (error) {
      if (_closed || generation != _generation) return;
      state = ComposeDiscoverState(
        calendar: state.calendar,
        cached: state.cached,
        updatedAt: state.updatedAt,
        error: error,
      );
    }
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    super.dispose();
  }
}
