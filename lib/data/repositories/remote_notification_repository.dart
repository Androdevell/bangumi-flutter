import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';
import '../../core/network/api_client.dart';
import '../../domain/models/notification.dart';
import '../../domain/repositories/notification_repository.dart';

class RemoteNotificationRepository implements NotificationRepository {
  RemoteNotificationRepository(this.api);
  final ApiClient api;
  @override
  SessionScope get scope => api.sessionScope;
  @override
  Listenable get sessionChanges => api.sessionChanges;
  void _check(SessionScope expected) {
    if (expected != scope) throw const ApiException('commentSessionChanged');
    if (scope.username.isEmpty) throw const ApiException('loginRequired');
  }

  @override
  Future<ComposeNoticeBatch> load({required bool unreadOnly}) async {
    final expected = scope;
    _check(expected);
    final json = await api.get(
      'p1/notify',
      query: {'limit': '40', if (unreadOnly) 'unread': 'true'},
      fresh: true,
    );
    _check(expected);
    if (json is! Map || json['data'] is! List || json['total'] is! num) {
      throw const FormatException('Invalid notifications');
    }
    final items =
        (json['data'] as List)
            .whereType<Map>()
            .take(40)
            .map(
              (item) => ComposeNotice.fromJson(Map<String, dynamic>.from(item)),
            )
            .where((item) => item.id > 0)
            .toList();
    return ComposeNoticeBatch(
      items,
      (json['total'] as num).toInt().clamp(0, 1 << 30),
    );
  }

  @override
  Future<void> markRead(
    Set<int> ids, {
    required SessionScope expectedScope,
  }) async {
    _check(expectedScope);
    if (ids.isEmpty) return; // 绝不以空 body 调用服务端“清空全部”语义。
    if (ids.length > 40 || ids.any((id) => id <= 0)) {
      throw ArgumentError('Invalid notification IDs');
    }
    await api.post(
      'p1/clear-notify',
      body: {'id': ids.toList()},
      expectedScope: expectedScope,
      requiresAuth: true,
      invalidatePaths: {'p1/notify'},
    );
    _check(expectedScope);
  }
}
