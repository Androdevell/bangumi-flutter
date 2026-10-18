import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';
import '../../core/network/api_client.dart';
import '../../domain/models/privacy_settings.dart';
import '../../domain/repositories/privacy_repository.dart';

class RemotePrivacyRepository implements PrivacyRepository {
  RemotePrivacyRepository(this.api);
  final ApiClient api;
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
    final json = await api.get('p1/privacy', fresh: true);
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
      await api.patch(
        'p1/privacy',
        body: {'settings': patch},
        expectedScope: original.session,
        invalidatePaths: {'p1/privacy'},
      );
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
      throw const ApiException('privacyUnconfirmed', outcomeUnknown: true);
    }
  }
}
