import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';
import '../../core/network/api_client.dart';
import '../../domain/models/privacy_settings.dart';
import '../../domain/repositories/privacy_repository.dart';

class RemotePrivacyRepository implements PrivacyRepository {
  RemotePrivacyRepository(this.api, {Future<void> Function(Duration)? delay})
    : _delay = delay ?? Future<void>.delayed;
  final ApiClient api;
  final Future<void> Function(Duration) _delay;
  @override
  SessionScope get scope => api.sessionScope;
  @override
  Listenable get sessionChanges => api.sessionChanges;

  void _check(SessionScope expected) {
    if (expected != scope) throw const ApiException('commentSessionChanged');
    if (!api.isLoggedIn) throw const ApiException('loginRequired');
  }

  @override
  Future<ComposePrivacySettings> load() async {
    final session = scope;
    _check(session);
    final json = await api.privacy(scope: session);
    _check(session);
    try {
      return ComposePrivacySettings.fromJson(json, session);
    } on FormatException {
      throw const ApiException('privacyInvalid');
    }
  }

  @override
  Future<ComposePrivacySettings> save(
    ComposePrivacySettings original,
    Map<String, String> edits,
  ) async {
    _check(original.session);
    final patch = Map<String, String>.of(edits);
    if (patch.entries.any(
      (entry) =>
          !PrivacyField.values.contains(entry.key) ||
          !PrivacyField.options(entry.key).contains(entry.value),
    )) {
      throw const ApiException('fieldInvalid');
    }
    final current = await load();
    _check(original.session);
    if (patch.keys.any(
      (key) => current.settings[key] != original.settings[key],
    )) {
      throw const ApiException('privacyConflict');
    }
    if (patch.isEmpty) return current;
    // P1 接受部分 settings；不发送未编辑字段或任何 preferences/只读能力字段。
    try {
      final response = await api.privacy(
        settings: patch,
        scope: original.session,
      );
      if (response != null) {
        final applied = ComposePrivacySettings.fromJson(
          response,
          original.session,
        );
        if (patch.entries.any(
          (entry) => applied.settings[entry.key] != entry.value,
        )) {
          throw const ApiException('privacyUnconfirmed', outcomeUnknown: true);
        }
      }
    } on ApiException catch (error) {
      if ({400, 401, 403, 429}.contains(error.statusCode)) {
        throw ApiException(
          error.statusCode == 401 ? 'loginRequired' : 'privacyFailed',
          statusCode: error.statusCode,
        );
      }
      throw const ApiException('privacyUnconfirmed', outcomeUnknown: true);
    } on Object {
      throw const ApiException('privacyUnconfirmed', outcomeUnknown: true);
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final confirmed = await load();
        _check(original.session);
        if (patch.entries.any(
          (entry) => confirmed.settings[entry.key] != entry.value,
        )) {
          throw const ApiException('privacyUnconfirmed', outcomeUnknown: true);
        }
        return confirmed;
      } on Object {
        _check(original.session);
        if (attempt < 2) {
          await _delay(Duration(milliseconds: 350 * (attempt + 1)));
        }
      }
    }
    throw const ApiException('privacyUnconfirmed', outcomeUnknown: true);
  }
}
