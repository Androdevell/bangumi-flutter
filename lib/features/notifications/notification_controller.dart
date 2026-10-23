import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/models/notification.dart';
import '../../domain/repositories/notification_repository.dart';

@immutable
class ComposeNotificationState {
  const ComposeNotificationState({
    this.items = const [],
    this.unreadCount = 0,
    this.loading = false,
    this.marking = false,
    this.unreadOnly = false,
    this.error = false,
  });
  final List<ComposeNotice> items;
  final int unreadCount;
  final bool loading, marking, unreadOnly, error;
  ComposeNotificationState copyWith({
    List<ComposeNotice>? items,
    int? unreadCount,
    bool? loading,
    bool? marking,
    bool? unreadOnly,
    bool? error,
  }) => ComposeNotificationState(
    items: items == null ? this.items : List.unmodifiable(items),
    unreadCount: unreadCount ?? this.unreadCount,
    loading: loading ?? this.loading,
    marking: marking ?? this.marking,
    unreadOnly: unreadOnly ?? this.unreadOnly,
    error: error ?? this.error,
  );
}

/// 仅前台宿主调度轮询；请求与操作都属于捕获的账号，过期返回不写入新会话。
class NotificationController extends ChangeNotifier {
  NotificationController(this.repository) {
    repository.sessionChanges.addListener(_sessionChanged);
  }
  final NotificationRepository repository;
  ComposeNotificationState _state = const ComposeNotificationState();
  ComposeNotificationState get state => _state;
  int _generation = 0, _listRequest = 0, _unreadRequest = 0;
  bool _disposed = false, _polling = false;
  bool get loggedIn => repository.scope.username.isNotEmpty;
  void _emit(ComposeNotificationState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  void _sessionChanged() {
    _generation++;
    _listRequest++;
    _unreadRequest++;
    _emit(const ComposeNotificationState());
    unawaited(poll());
  }

  Future<void> poll() async {
    if (_polling || !loggedIn || _disposed || state.marking) return;
    _polling = true;
    final generation = _generation, request = ++_unreadRequest;
    final scope = repository.scope;
    try {
      final result = await repository.load(unreadOnly: true);
      if (!_disposed &&
          generation == _generation &&
          request == _unreadRequest &&
          scope == repository.scope) {
        _emit(state.copyWith(unreadCount: result.total));
      }
    } on Object {
      // 后台角标刷新失败不覆盖用户正在阅读的列表，也不把失败伪装为零未读。
    } finally {
      _polling = false;
    }
  }

  Future<void> refresh({bool? unreadOnly}) async {
    if (!loggedIn || _disposed || state.marking) return;
    final generation = _generation, request = ++_listRequest;
    final scope = repository.scope;
    final filter = unreadOnly ?? state.unreadOnly;
    _emit(
      state.copyWith(
        loading: true,
        error: false,
        unreadOnly: filter,
        items: filter == state.unreadOnly ? null : const [],
      ),
    );
    try {
      final result = await repository.load(unreadOnly: filter);
      if (_disposed ||
          generation != _generation ||
          request != _listRequest ||
          scope != repository.scope) {
        return;
      }
      _emit(
        state.copyWith(
          items: result.items,
          loading: false,
          unreadCount: filter ? result.total : null,
        ),
      );
      if (!filter) await poll();
    } on Object {
      if (!_disposed &&
          generation == _generation &&
          request == _listRequest &&
          scope == repository.scope) {
        _emit(state.copyWith(loading: false, error: true));
      }
    }
  }

  Future<bool> markRead(Set<int> ids) async {
    if (_disposed || state.marking || !loggedIn) return false;
    final visible =
        state.items
            .where((item) => item.unread && ids.contains(item.id))
            .map((item) => item.id)
            .toSet();
    if (visible.isEmpty) return true;
    final generation = _generation, scope = repository.scope;
    _listRequest++; // 旧列表与旧未读数不能覆盖已读操作。
    _unreadRequest++;
    _emit(state.copyWith(marking: true, loading: false, error: false));
    try {
      await repository.markRead(visible, expectedScope: scope);
      if (_disposed || generation != _generation || scope != repository.scope) {
        return false;
      }
      _emit(
        state.copyWith(
          marking: false,
          unreadCount: (state.unreadCount - visible.length).clamp(0, 1 << 30),
          items:
              state.items
                  .map((item) => visible.contains(item.id) ? item.read() : item)
                  .where((item) => !state.unreadOnly || item.unread)
                  .toList(),
        ),
      );
      unawaited(poll());
      return true;
    } on Object {
      if (!_disposed &&
          generation == _generation &&
          scope == repository.scope) {
        _emit(state.copyWith(marking: false, error: true));
      }
      return false;
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
