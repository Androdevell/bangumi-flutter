import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';

@immutable
class ComposePrivateMessage {
  const ComposePrivateMessage({
    required this.id,
    required this.title,
    required this.content,
    required this.sender,
    this.time = '',
    this.path = '',
    this.unread = false,
  });
  final int id;
  final String title, content, sender, time, path;
  final bool unread;
}

@immutable
class ComposePrivatePage {
  ComposePrivatePage(List<ComposePrivateMessage> items, this.hasMore)
    : items = List.unmodifiable(items);
  final List<ComposePrivateMessage> items;
  final bool hasMore;
}

@immutable
class ComposePrivateForm {
  ComposePrivateForm(
    this.source,
    this.action,
    Map<String, String> fields,
    this.scope,
  ) : fields = Map.unmodifiable(fields);
  final String source, action;
  final Map<String, String> fields;
  final SessionScope scope;
}

abstract interface class PrivateMessageRepository {
  SessionScope get scope;
  Listenable get sessionChanges;
  Future<ComposePrivatePage> load({String folder = 'inbox', int page = 1});
  Future<List<ComposePrivateMessage>> thread(String path);
  Future<ComposePrivateForm> form({String recipient = '', String? threadPath});
  Future<void> send(
    ComposePrivateForm form, {
    required String recipient,
    required String title,
    required String content,
  });
}

abstract interface class PrivateMessageFeature {
  PrivateMessageRepository get messages;
}
