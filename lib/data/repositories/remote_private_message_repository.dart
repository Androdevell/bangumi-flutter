import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import '../../app/state/session_scope.dart';
import '../../core/network/api_client.dart';
import '../../domain/repositories/private_message_repository.dart';

class RemotePrivateMessageRepository implements PrivateMessageRepository {
  RemotePrivateMessageRepository(this.api);
  final ApiClient api;
  @override
  SessionScope get scope => api.sessionScope;
  @override
  Listenable get sessionChanges => api.sessionChanges;
  void _check(SessionScope expected) {
    if (scope != expected) throw const ApiException('commentSessionChanged');
    if (scope.username.isEmpty) throw const ApiException('loginRequired');
  }

  static bool validThread(String path) =>
      RegExp(r'^/pm/(?:view|conversation)/[1-9]\d*\.chii$').hasMatch(path);
  @override
  Future<ComposePrivatePage> load({
    String folder = 'inbox',
    int page = 1,
  }) async {
    if (!{'inbox', 'outbox'}.contains(folder) || page < 1) {
      throw const ApiException('fieldInvalid');
    }
    final expected = scope;
    _check(expected);
    final response = await api.siteDocument(
      '/pm/$folder.chii?page=$page',
      scope: expected,
    );
    _check(expected);
    if (response.redirect != null) {
      throw const ApiException('messageUnavailable');
    }
    return parseList(response.html, page);
  }

  static ComposePrivatePage parseList(String source, int page) {
    final doc = html.parse(source);
    if (doc.querySelector(
          '#pmForm, #pm_sidebar, #pm_main, .pmList, .pm-conversation-scroll',
        ) ==
        null) {
      throw const ApiException('messageUnavailable');
    }
    final items = <ComposePrivateMessage>[];
    final ids = <int>{};
    for (final link in doc.querySelectorAll('a[href]')) {
      final uri = Uri.parse(
        'https://bgm.tv/',
      ).resolve(link.attributes['href']!);
      if (uri.host != 'bgm.tv' || !validThread(uri.path)) continue;
      final id = int.parse(
        RegExp(r'(\d+)\.chii$').firstMatch(uri.path)!.group(1)!,
      );
      if (!ids.add(id)) continue;
      Element row = link;
      while (row.parent != null &&
          !{'tr', 'li'}.contains(row.localName) &&
          !row.classes.contains('item') &&
          !row.classes.contains('pm-conversation-item')) {
        row = row.parent!;
      }
      items.add(
        ComposePrivateMessage(
          id: id,
          path: uri.path,
          title:
              row.querySelector('.pm-conversation-name')?.text.trim() ??
              link.text.trim(),
          content:
              row.querySelector('.pm-conversation-desc, .tip')?.text.trim() ??
              '',
          sender:
              row
                  .querySelector('.pm-conversation-name, .sub_title a')
                  ?.text
                  .trim() ??
              '',
          time:
              row
                  .querySelector('.pm-conversation-date, small.grey')
                  ?.text
                  .trim() ??
              '',
          unread: row.querySelector('.pm_new, .pm-conversation-unread') != null,
        ),
      );
    }
    final more = doc.querySelectorAll('a[href]').any((a) {
      final u = Uri.tryParse(a.attributes['href']!);
      return int.tryParse(u?.queryParameters['page'] ?? '0') == page + 1;
    });
    return ComposePrivatePage(items, more);
  }

  @override
  Future<List<ComposePrivateMessage>> thread(String path) async {
    if (!validThread(path)) throw const ApiException('fieldInvalid');
    final expected = scope;
    _check(expected);
    final response = await api.siteDocument(path, scope: expected);
    _check(expected);
    final doc = html.parse(response.html);
    final result = <ComposePrivateMessage>[];
    for (final item in doc.querySelectorAll(
      '.pm-chat-panel .pm-message-list .pm-message',
    )) {
      final body = item.querySelector('.pm-message-body');
      if (body == null) continue;
      for (final br in body.querySelectorAll('br')) {
        br.replaceWith(Text('\n'));
      }
      for (final p in body.querySelectorAll('p')) {
        p.append(Text('\n'));
      }
      result.add(
        ComposePrivateMessage(
          id: int.tryParse(item.id.replaceFirst('msg_', '')) ?? result.length,
          title: '',
          content: body.text.trim(),
          sender:
              item
                  .querySelector('a.avatar')
                  ?.attributes['href']
                  ?.split('/')
                  .last ??
              '',
          time: item.querySelector('.pm-message-info small')?.text.trim() ?? '',
        ),
      );
    }
    for (final item
        in result.isEmpty
            ? doc.querySelectorAll('#comment_box > .item')
            : <Element>[]) {
      final text = item.querySelector('.text_pm');
      if (text == null) continue;
      final sender = text.querySelector('a.l')?.text.trim() ?? '';
      final time = text.querySelector('small.grey')?.text.trim() ?? '';
      text.querySelector('.rr')?.remove();
      text.querySelector('a.l')?.remove();
      result.add(
        ComposePrivateMessage(
          id: result.length,
          title: '',
          content: text.text.trim(),
          sender: sender,
          time: time,
        ),
      );
    }
    if (result.isEmpty) throw const ApiException('messageUnavailable');
    return result;
  }

  @override
  Future<ComposePrivateForm> form({
    String recipient = '',
    String? threadPath,
  }) async {
    if (threadPath != null && !validThread(threadPath)) {
      throw const ApiException('fieldInvalid');
    }
    if (recipient.isNotEmpty && !RegExp(r'^[\w-]{1,80}$').hasMatch(recipient)) {
      throw const ApiException('fieldInvalid');
    }
    final expected = scope;
    _check(expected);
    final source =
        threadPath ??
        '/pm/compose.chii${recipient.isEmpty ? '' : '?uid=${Uri.encodeQueryComponent(recipient)}'}';
    final response = await api.siteDocument(source, scope: expected);
    _check(expected);
    final doc = html.parse(response.html);
    final form =
        doc.querySelector('#pmReplyForm') ?? doc.querySelector('#pmForm');
    if (form == null || form.querySelector('[name="msg_body"]') == null) {
      throw const ApiException('messageUnavailable');
    }
    final action = Uri.parse(
      'https://bgm.tv$source',
    ).resolve(form.attributes['action'] ?? '');
    if (action.scheme != 'https' ||
        action.host != 'bgm.tv' ||
        action.port != 443 ||
        action.userInfo.isNotEmpty ||
        !RegExp(r'^/pm/(?:create|compose)\.chii$').hasMatch(action.path)) {
      throw const ApiException('messageUnavailable');
    }
    final fields = <String, String>{};
    for (final element in form.querySelectorAll('input,textarea')) {
      final name = element.attributes['name'];
      if (name == null ||
          name.isEmpty ||
          element.attributes['type'] == 'file') {
        continue;
      }
      fields[name] =
          element.localName == 'textarea'
              ? element.text
              : element.attributes['value'] ?? '';
    }
    if ((fields['formhash'] ?? '').isEmpty) {
      throw const ApiException('profileWebLoginRequired');
    }
    return ComposePrivateForm(source, action.path, fields, expected);
  }

  @override
  Future<void> send(
    ComposePrivateForm original, {
    required String recipient,
    required String title,
    required String content,
  }) async {
    _check(original.scope);
    if (content.trim().isEmpty ||
        content.characters.length > 10000 ||
        title.characters.length > 200 ||
        recipient.trim().isEmpty) {
      throw const ApiException('fieldInvalid');
    }
    final fresh = await form(
      recipient: validThread(Uri.parse(original.source).path) ? '' : recipient,
      threadPath:
          validThread(Uri.parse(original.source).path) ? original.source : null,
    );
    _check(original.scope);
    final response = await api.siteDocument(
      fresh.action,
      scope: original.scope,
      fields: {
        ...fresh.fields,
        'msg_receivers': recipient.trim(),
        'msg_title': title.trim(),
        'msg_body': content.trim(),
      },
    );
    if (scope != original.scope) {
      throw const ApiException('commentSessionChanged', outcomeUnknown: true);
    }
    final redirect = response.redirect?.path;
    if (redirect != null &&
        (validThread(redirect) ||
            {'/pm/outbox.chii', '/pm/inbox.chii'}.contains(redirect))) {
      return;
    }
    final notice =
        html.parse(response.html).querySelector('#colunmNotice .text')?.text ??
        '';
    if (notice.contains('短消息已发送') || notice.contains('短信发送成功')) return;
    throw const ApiException('messageUnknown', outcomeUnknown: true);
  }
}
