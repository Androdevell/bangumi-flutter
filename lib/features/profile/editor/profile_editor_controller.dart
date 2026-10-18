import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../domain/models/account_settings.dart';
import '../../../domain/repositories/account_settings_repository.dart';
import '../../../app/state/session_scope.dart';

@immutable
class ComposeProfileEditorState {
  const ComposeProfileEditorState({
    this.original,
    this.loading = false,
    this.saving = false,
    this.stale = false,
    this.unknown = false,
    this.error,
  });
  final ComposeAccountSettings? original;
  final bool loading, saving, stale, unknown;
  final Object? error;
}

class ProfileEditorController extends ChangeNotifier {
  ProfileEditorController(this.repository) : _session = repository.scope {
    repository.sessionChanges.addListener(_changed);
  }
  final AccountSettingsRepository repository;
  final SessionScope _session;
  ComposeProfileEditorState state = const ComposeProfileEditorState();
  int _generation = 0;
  bool _closed = false;
  void _changed() {
    _generation++;
    state = ComposeProfileEditorState(original: state.original, stale: true);
    notifyListeners();
  }

  Future<void> load() async {
    if (state.stale || state.saving) return;
    final generation = ++_generation;
    final unknown = state.unknown;
    state = ComposeProfileEditorState(
      original: state.original,
      loading: true,
      unknown: unknown,
    );
    notifyListeners();
    try {
      final data = await repository.load();
      if (_closed ||
          generation != _generation ||
          _session != repository.scope) {
        return;
      }
      state = ComposeProfileEditorState(original: data);
    } on Object catch (error) {
      if (_closed || generation != _generation) return;
      state = ComposeProfileEditorState(
        original: state.original,
        error: error,
        unknown: unknown,
      );
    }
    notifyListeners();
  }

  Future<bool> save(Map<String, String> edits, {Uint8List? avatar}) async {
    final original = state.original;
    if (original == null ||
        state.stale ||
        state.saving ||
        state.loading ||
        state.unknown) {
      return false;
    }
    final generation = ++_generation;
    state = ComposeProfileEditorState(original: original, saving: true);
    notifyListeners();
    try {
      final data = await repository.save(original, edits, avatar: avatar);
      if (_closed ||
          generation != _generation ||
          _session != repository.scope) {
        return false;
      }
      state = ComposeProfileEditorState(original: data);
      notifyListeners();
      return true;
    } on Object catch (error) {
      if (_closed || generation != _generation) return false;
      state = ComposeProfileEditorState(
        original: original,
        error: error,
        unknown: error is ApiException && error.outcomeUnknown,
      );
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    repository.sessionChanges.removeListener(_changed);
    super.dispose();
  }
}
