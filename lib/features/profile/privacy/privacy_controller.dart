import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../domain/models/privacy_settings.dart';
import '../../../domain/repositories/privacy_repository.dart';

class PrivacyController extends ChangeNotifier {
  PrivacyController(this.repository) {
    repository.sessionChanges.addListener(_sessionChanged);
  }
  final PrivacyRepository repository;
  ComposePrivacySettings? _original;
  final Map<String, String> _edits = {};
  Map<String, String> get values =>
      Map.unmodifiable({...?_original?.settings, ..._edits});
  bool busy = false;
  bool uncertain = false;
  Object? error;
  bool _disposed = false;
  int _generation = 0;
  bool get loaded => _original != null;
  int get editCount => _edits.length;
  bool get canSave => loaded && !busy && !uncertain && _edits.isNotEmpty;

  void _sessionChanged() {
    _generation++;
    _original = null;
    _edits.clear();
    busy = false;
    uncertain = false;
    error = const ApiException('commentSessionChanged');
    notifyListeners();
  }

  Future<void> load() async {
    if (busy) return;
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final value = await repository.load();
      if (_disposed || generation != _generation) return;
      _original = value;
      _edits.clear();
      uncertain = false;
    } on Object catch (failure) {
      if (_disposed || generation != _generation) return;
      _original = null;
      error = failure;
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void edit(String field, String value) {
    if (!loaded ||
        busy ||
        uncertain ||
        !PrivacyField.values.contains(field) ||
        !PrivacyField.options(field).contains(value)) {
      return;
    }
    if (_original!.settings[field] == value) {
      _edits.remove(field);
    } else {
      _edits[field] = value;
    }
    error = null;
    notifyListeners();
  }

  Future<bool> save() async {
    if (!canSave) return false;
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.save(_original!, Map.of(_edits));
      if (_disposed || generation != _generation) return false;
      _original = result;
      _edits.clear();
      return true;
    } on Object catch (failure) {
      if (_disposed || generation != _generation) return false;
      error = failure;
      uncertain = failure is ApiException && failure.outcomeUnknown;
      // 冲突不能直接重试旧表单；必须重新读取再编辑。
      if (failure is ApiException && failure.message == 'privacyConflict') {
        uncertain = true;
      }
      return false;
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    repository.sessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }
}
