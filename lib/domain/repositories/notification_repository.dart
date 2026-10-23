import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';
import '../models/notification.dart';

abstract interface class NotificationRepository {
  SessionScope get scope;
  Listenable get sessionChanges;
  Future<ComposeNoticeBatch> load({required bool unreadOnly});
  Future<void> markRead(Set<int> ids, {required SessionScope expectedScope});
}

abstract interface class NotificationFeature {
  NotificationRepository get notifications;
}
