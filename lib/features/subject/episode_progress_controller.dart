import 'package:flutter/foundation.dart';
import '../../core/paged.dart';
import '../../core/subject_detail_models.dart';
import '../../domain/repositories/episode_progress_repository.dart';

@immutable
class ComposeEpisodeProgressState {
  const ComposeEpisodeProgressState({
    this.page,
    this.loading = false,
    this.busyId,
    this.error,
    this.saved = false,
  });
  final Paged<SubjectEpisode>? page;
  final bool loading, saved;
  final int? busyId;
  final Object? error;
}

class EpisodeProgressController extends ChangeNotifier {
  EpisodeProgressController(this.repository, this.subjectId) {
    repository.sessionChanges.addListener(_sessionChanged);
  }
  final EpisodeProgressRepository repository;
  final int subjectId;
  ComposeEpisodeProgressState state = const ComposeEpisodeProgressState();
  int _generation = 0;
  bool _closed = false;
  void _sessionChanged() {
    state = const ComposeEpisodeProgressState();
    refresh(reset: true);
  }

  Future<void> refresh({int? offset, bool reset = false}) async {
    if (_closed || (state.busyId != null && !reset)) return;
    final generation = ++_generation;
    final previous = reset ? null : state.page;
    state = ComposeEpisodeProgressState(
      page: previous,
      loading: true,
      busyId: state.busyId,
      saved: state.saved,
    );
    notifyListeners();
    try {
      final result = await repository.load(
        subjectId,
        offset: offset ?? previous?.offset ?? 0,
        fresh: true,
      );
      if (_closed || generation != _generation) return;
      state = ComposeEpisodeProgressState(page: result, saved: state.saved);
    } on Object catch (error) {
      if (_closed || generation != _generation) return;
      state = ComposeEpisodeProgressState(
        page: previous,
        error: error,
        saved: state.saved,
      );
    }
    notifyListeners();
  }

  Future<void> save(
    SubjectEpisode episode,
    int status, {
    bool batch = false,
  }) async {
    if (_closed || state.busyId != null) return;
    final session = repository.scope;
    final generation = ++_generation;
    state = ComposeEpisodeProgressState(page: state.page, busyId: episode.id);
    notifyListeners();
    try {
      await repository.save(
        subjectId,
        episode.id,
        status,
        session: session,
        batch: batch,
      );
      if (_closed || generation != _generation || session != repository.scope) {
        return;
      }
      state = ComposeEpisodeProgressState(page: state.page, saved: true);
      await refresh();
    } on Object catch (error) {
      if (_closed || generation != _generation) return;
      state = ComposeEpisodeProgressState(page: state.page, error: error);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    repository.sessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }
}
