import 'package:html/parser.dart' as html;
import '../../app/state/session_scope.dart';
import '../../core/network/api_client.dart';
import '../../domain/models/privacy_settings.dart';

/// 对应官网 privacy_set 的字段，值以网页选项为准，不发送黑名单表单。
const webPrivacyFields = {
  PrivacyField.privateMessage: 'privacy_set[1]',
  PrivacyField.timelineReply: 'privacy_set[30]',
  PrivacyField.timelineCollectReply: 'privacy_set[32]',
  PrivacyField.follow: 'privacy_set[40]',
  PrivacyField.mentionNotification: 'privacy_set[20]',
  PrivacyField.commentNotification: 'privacy_set[21]',
  PrivacyField.friendNotification: 'privacy_set[23]',
};
const webPrivacyAudiences = {
  PrivacyAudience.all: '0',
  PrivacyAudience.friends: '1',
  PrivacyAudience.none: '2',
};

({ComposePrivacySettings settings, String formHash}) parseWebPrivacy(
  String text,
  SessionScope session,
) {
  final document = html.parse(text);
  if (document.querySelector('#loginForm, .guest') != null) {
    throw const ApiException('profileWebLoginRequired');
  }
  final identity =
      document.querySelector('.idBadgerNeue a.avatar')?.attributes['href'];
  final username =
      identity == null ? null : Uri.tryParse(identity)?.pathSegments.lastOrNull;
  if (username != null &&
      username != session.username &&
      !(session.accountId > 0 && username == session.accountId.toString())) {
    throw const ApiException('profileWebLoginRequired');
  }
  var form = document.querySelector('select[name="privacy_set[1]"]')?.parent;
  while (form != null && form.localName != 'form') {
    form = form.parent;
  }
  if (form == null ||
      (form.attributes['method'] ?? '').toLowerCase() != 'post') {
    throw const ApiException('privacyInvalid');
  }
  final action = Uri.parse(
    'https://bgm.tv/settings/privacy',
  ).resolve(form.attributes['action'] ?? '');
  if (action.scheme != 'https' ||
      action.host != 'bgm.tv' ||
      action.port != 443 ||
      action.userInfo.isNotEmpty ||
      action.path != '/settings/privacy') {
    throw const ApiException('privacyInvalid');
  }
  // 实际页面存在嵌套的屏蔽用户表单，必须只取隐私表单的令牌与七个 select。
  final hash =
      form
          .querySelector('input[name="formhash"]')
          ?.attributes['value']
          ?.trim() ??
      '';
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(hash)) {
    throw const ApiException('profileTokenMissing');
  }
  final values = <String, String>{};
  for (final entry in webPrivacyFields.entries) {
    final selects = form.querySelectorAll('select[name="${entry.value}"]');
    if (selects.length != 1 ||
        selects.single.attributes.containsKey('disabled')) {
      throw const ApiException('privacyInvalid');
    }
    final options = selects.single.querySelectorAll('option');
    final selected =
        options.where((o) => o.attributes.containsKey('selected')).toList();
    if (options.isEmpty || selected.length > 1) {
      throw const ApiException('privacyInvalid');
    }
    final value =
        (selected.isEmpty ? options.first : selected.single)
            .attributes['value'];
    final matches =
        webPrivacyAudiences.entries.where((e) => e.value == value).toList();
    if (matches.length != 1 ||
        !PrivacyField.options(entry.key).contains(matches.single.key)) {
      throw const ApiException('privacyInvalid');
    }
    for (final audience in PrivacyField.options(entry.key)) {
      if (!options.any(
        (o) => o.attributes['value'] == webPrivacyAudiences[audience],
      )) {
        throw const ApiException('privacyInvalid');
      }
    }
    values[entry.key] = matches.single.key;
  }
  return (
    settings: ComposePrivacySettings(session: session, settings: values),
    formHash: hash,
  );
}
