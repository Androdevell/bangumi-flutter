import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';
import '../../app/state/session_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/network/app_image_cache.dart';
import '../../core/media/avatar_revision.dart';
import '../../domain/models/account_settings.dart';
import '../../domain/repositories/account_settings_repository.dart';

class RemoteAccountSettingsRepository implements AccountSettingsRepository {
  RemoteAccountSettingsRepository(this.api, {required this.onChanged});
  final ApiClient api;
  final VoidCallback onChanged;
  @override
  SessionScope get scope => api.sessionScope;
  @override
  Listenable get sessionChanges => api.sessionChanges;
  @override
  Future<ComposeAccountSettings> load() async {
    final session = scope;
    final text = await api.accountSettings(scope: session);
    if (session != scope) throw const ApiException('commentSessionChanged');
    return parseAccountSettings(text, session);
  }

  @override
  Future<ComposeAccountSettings> save(
    ComposeAccountSettings original,
    Map<String, String> edits, {
    Uint8List? avatar,
  }) async {
    if (original.session != scope) {
      throw const ApiException('commentSessionChanged');
    }
    if (avatar != null && (avatar.isEmpty || avatar.length > 5 * 1024 * 1024)) {
      throw const ApiException('fieldInvalid');
    }
    final allowed = {
      ...ComposeAccountSettings.editableFields,
      if (original.restrictedField != null) original.restrictedField!,
    };
    if (edits.keys.any((key) => !allowed.contains(key))) {
      throw const ApiException('fieldInvalid');
    }
    // 重新读取最新隐藏字段及未编辑的资料，避免将旧表单整份覆盖回去。
    final current = await load();
    if (current.session != original.session) {
      throw const ApiException('commentSessionChanged');
    }
    for (final key in edits.keys) {
      if (current.value(key) != original.value(key)) {
        throw const ApiException('profileUnconfirmed');
      }
    }
    final fields = {...current.fields, ...edits, 'submit': 'submit'};
    for (final key in current.checkboxNames) {
      if (fields[key]?.isEmpty ?? false) fields.remove(key);
    }
    final response = await api.accountSettings(
      scope: original.session,
      fields: fields,
      avatar: avatar,
    );
    if (response.isNotEmpty) {
      final document = html.parse(response);
      if (document.querySelector('#loginForm') != null ||
          (document.querySelector('input[name="nickname"]') == null &&
              document.querySelector('input[type="password"]') != null)) {
        throw const ApiException('loginRequired');
      }
      if (document.querySelector(
            '.error, .errorMessage, #colunmNotice .error',
          ) !=
          null) {
        throw const ApiException('saveFailed');
      }
      final notice =
          document.querySelector('#colunmNotice .text')?.text.trim() ?? '';
      if (notice.isNotEmpty &&
          !RegExp('成功|success|保存しました', caseSensitive: false).hasMatch(notice)) {
        throw const ApiException('saveFailed');
      }
    }
    ComposeAccountSettings confirmed;
    try {
      confirmed = await load();
    } on Object {
      throw const ApiException('profileUnconfirmed', outcomeUnknown: true);
    }
    for (final entry in edits.entries) {
      if (confirmed.value(entry.key).trim() != entry.value.trim()) {
        throw const ApiException('profileUnconfirmed', outcomeUnknown: true);
      }
    }
    api.invalidateResources({
      'p1/me',
      'p1/users/${Uri.encodeComponent(scope.username)}',
    });
    try {
      if (avatar != null && confirmed.avatarUrl.isNotEmpty) {
        await AppImageCache.manager.removeFile(confirmed.avatarUrl);
        AvatarRevision.bump(confirmed.avatarUrl);
      }
      await api.updateProfileIdentity(
        scope: original.session,
        nickname: confirmed.value('nickname'),
        avatarUrl: AvatarRevision.resolve(confirmed.avatarUrl),
      );
    } on Object {
      throw const ApiException('profileUnconfirmed', outcomeUnknown: true);
    }
    onChanged();
    return confirmed;
  }
}

/// 按表单 name 读取，不依赖网页语言，也不会把其他账号安全表单混入保存。
ComposeAccountSettings parseAccountSettings(String text, SessionScope session) {
  final document = html.parse(text);
  final nickname = document.querySelector('input[name="nickname"]');
  final form = _ancestor(nickname, 'form');
  if (form == null || document.querySelector('#loginForm') != null) {
    throw const ApiException('profileFormInvalid');
  }
  final fields = <String, String>{};
  final checkboxes = <String>{};
  final checkboxValues = <String, String>{};
  final limits = <String, int>{};
  String? restricted;
  for (final input in form.querySelectorAll(
    'input[name], textarea[name], select[name]',
  )) {
    final name = input.attributes['name']!;
    final type = input.attributes['type']?.toLowerCase() ?? 'text';
    if (input.attributes.containsKey('disabled') ||
        const {
          'file',
          'button',
          'reset',
          'submit',
          'password',
        }.contains(type)) {
      continue;
    }
    if (type == 'checkbox' || type == 'radio') {
      checkboxes.add(name);
      checkboxValues[name] = input.attributes['value'] ?? 'on';
      if (input.attributes.containsKey('checked')) {
        fields[name] = input.attributes['value'] ?? 'on';
      }
      final label = _ancestor(input, 'label') ?? _ancestor(input, 'tr');
      if (type == 'checkbox' &&
          label != null &&
          label.querySelectorAll('input[type="checkbox"]').length == 1 &&
          RegExp('受限|NSFW', caseSensitive: false).hasMatch(label.text)) {
        restricted = name;
      }
    } else if (input.localName == 'textarea') {
      fields[name] = input.text;
    } else if (input.localName == 'select') {
      final selected =
          input.querySelector('option[selected]') ??
          input.querySelector('option');
      fields[name] = selected?.attributes['value'] ?? selected?.text ?? '';
    } else if (type == 'hidden' ||
        ComposeAccountSettings.editableFields.contains(name)) {
      fields[name] = input.attributes['value'] ?? '';
    }
    final limit = int.tryParse(input.attributes['maxlength'] ?? '');
    if (limit != null && limit > 0) limits[name] = limit;
  }
  final zones = <String, String>{
    for (final option in form.querySelectorAll(
      'select[name="timeoffsetnew"] option',
    ))
      option.attributes['value'] ?? option.text: option.text,
  };
  if (fields['formhash']?.isNotEmpty != true ||
      !ComposeAccountSettings.editableFields.every(fields.containsKey) ||
      zones.isEmpty) {
    throw const ApiException('profileFormInvalid');
  }
  var avatar =
      _ancestor(
        form.querySelector('input[name="picfile"]'),
        'tr',
      )?.querySelector('img')?.attributes['src'] ??
      '';
  if (avatar.startsWith('//')) avatar = 'https:$avatar';
  final site = form.querySelector('input[name="newsite"]');
  final siteText = site?.parent?.text ?? '';
  final prefix =
      siteText.contains('https://')
          ? 'https://'
          : siteText.contains('http://')
          ? 'http://'
          : '';
  return ComposeAccountSettings(
    session: session,
    fields: fields,
    timezones: zones,
    checkboxNames: checkboxes,
    checkboxValues: checkboxValues,
    maxLengths: limits,
    avatarUrl: avatar,
    sitePrefix: prefix,
    restrictedField: restricted,
  );
}

Element? _ancestor(Element? element, String tag) {
  for (var current = element; current != null; current = current.parent) {
    if (current.localName == tag) return current;
  }
  return null;
}
