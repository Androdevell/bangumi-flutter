import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';
import '../../core/network/api_client.dart';
import '../../domain/models/privacy_settings.dart';
import '../../domain/repositories/privacy_repository.dart';
import 'web_privacy_form.dart';

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
    final text = await api.privacySettings(scope: session);
    _check(session);
    try {
      return parseWebPrivacy(text, session).settings;
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
    final fresh = parseWebPrivacy(
      await api.privacySettings(scope: original.session),
      original.session,
    );
    final current = fresh.settings;
    _check(original.session);
    if (patch.keys.any(
      (key) => current.settings[key] != original.settings[key],
    )) {
      throw const ApiException('privacyConflict');
    }
    if (patch.isEmpty) return current;
    // 网页按整份隐私表单保存；未编辑项取刚读取的服务器值，防止重置为默认。
    final values = {...current.settings, ...patch};
    try {
      await api.privacySettings(
        fields: {
          for (final entry in webPrivacyFields.entries)
            entry.value: webPrivacyAudiences[values[entry.key]]!,
          'formhash': fresh.formHash,
          'submit_privacy': '保存',
        },
        scope: original.session,
      );
    } on ApiException catch (error) {
      if (error.message == 'profileWebLoginRequired') rethrow;
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
      } on Object catch (error) {
        _check(original.session);
        if (error is ApiException &&
            error.message == 'profileWebLoginRequired') {
          throw const ApiException(
            'profileWebLoginRequired',
            outcomeUnknown: true,
          );
        }
        if (attempt < 2) {
          await _delay(Duration(milliseconds: 350 * (attempt + 1)));
        }
      }
    }
    throw const ApiException('privacyUnconfirmed', outcomeUnknown: true);
  }
}
