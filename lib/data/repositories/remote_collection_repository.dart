import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';
import '../../core/community_models.dart';
import '../../core/network/api_client.dart';
import '../../core/paged.dart';
import '../../domain/events/collection_changed.dart';
import '../../domain/models/collection_models.dart';
import '../../domain/repositories/collection_repository.dart';

class RemoteCollectionRepository implements CollectionRepository {
  RemoteCollectionRepository(this._api) {
    _api.sessionChanges.addListener(_resetSession);
  }

  final ApiClient _api;
  final _changes = StreamController<CollectionChanged>.broadcast(sync: true);
  final Map<int, Future<void>> _writes = {};
  final Map<(SessionScope, int), int> _confirmedStatuses = {};
  int _revision = 0;
  bool _closed = false;

  @override
  Stream<CollectionChanged> get changes => _changes.stream;
  @override
  Listenable get sessionChanges => _api.sessionChanges;
  @override
  SessionScope get sessionScope => _api.sessionScope;

  void _resetSession() {
    _revision++;
    _confirmedStatuses.clear();
  }

  @override
  Future<Paged<ComposeCollectionItem>> query(
    CollectionQuery query, {
    int offset = 0,
    bool fresh = false,
  }) async {
    if (query.username.isEmpty ||
        offset < 0 ||
        (query.subjectType != null &&
            !SubjectType.values.contains(query.subjectType)) ||
        (query.status != null &&
            !CollectionStatus.values.contains(query.status))) {
      throw const ApiException('收藏查询参数不正确');
    }
    const limit = 40;
    final self = _api.isLoggedIn && query.username == _api.currentUsername;
    final result = await _api.get(
      self
          ? 'p1/collections/subjects'
          : 'p1/users/${Uri.encodeComponent(query.username)}/collections/subjects',
      fresh: fresh,
      query: {
        'limit': '$limit',
        'offset': '$offset',
        if (query.subjectType != null) 'subjectType': '${query.subjectType}',
        if (query.status != null) 'type': '${query.status}',
      },
    );
    if (result is! Map || result['data'] is! List) {
      throw const ApiException('收藏列表格式不正确');
    }
    final items = <ComposeCollectionItem>[];
    for (final raw in result['data'] as List) {
      if (raw is! Map) throw const ApiException('收藏条目格式不正确');
      final item = UserContentItem.fromSubject(Map<String, dynamic>.from(raw));
      if (item.id <= 0) throw const ApiException('收藏条目缺少 ID');
      items.add(ComposeCollectionItem(item));
    }
    return Paged(
      items: items,
      offset: offset,
      limit: limit,
      total: result['total'] is int ? result['total'] as int : null,
    );
  }

  @override
  Future<CollectionChanged> save(
    int subjectId,
    CollectionPatch patch, {
    required SessionScope scope,
  }) async {
    if (subjectId <= 0 ||
        patch.toJson().isEmpty ||
        (patch.type != null && !CollectionStatus.values.contains(patch.type)) ||
        (patch.rate != null && (patch.rate! < 0 || patch.rate! > 10))) {
      throw const ApiException('不支持的收藏操作或参数');
    }
    final previousWrite = _writes[subjectId];
    final done = Completer<void>();
    _writes[subjectId] = done.future;
    try {
      if (previousWrite != null) await previousWrite;
      _requireScope(scope);
      final subject = await _api.get('p1/subjects/$subjectId', fresh: true);
      _requireScope(scope);
      if (subject is! Map || subject['id'] != subjectId) {
        throw const ApiException('无法核对现有收藏状态');
      }
      final interest = subject['interest'];
      final readStatus =
          interest == null
              ? 0
              : interest is Map && interest['type'] is int
              ? interest['type'] as int
              : -1;
      if (readStatus != 0 && !CollectionStatus.values.contains(readStatus)) {
        throw const ApiException('无法核对现有收藏状态');
      }
      final previousStatus =
          _confirmedStatuses[(scope, subjectId)] ?? readStatus;
      final nextStatus = patch.type ?? previousStatus;
      if (!CollectionStatus.values.contains(nextStatus)) {
        throw const ApiException('新收藏必须选择收藏状态');
      }
      await _api.put(
        'p1/collections/subjects/$subjectId',
        body: patch.toJson(),
        expectedScope: scope,
        invalidatePaths: {
          'p1/collections/',
          'p1/users/${Uri.encodeComponent(scope.username)}',
          'p1/home',
          'p1/subjects/$subjectId',
        },
      );
      _requireScope(scope);
      if (readStatus == nextStatus) {
        _confirmedStatuses.remove((scope, subjectId));
      } else {
        _confirmedStatuses[(scope, subjectId)] = nextStatus;
      }
      final change = CollectionChanged(
        session: scope,
        subjectId: subjectId,
        previousStatus: previousStatus,
        nextStatus: nextStatus,
        revision: ++_revision,
        fields: patch.toJson().keys.toSet(),
      );
      _changes.add(change);
      return change;
    } finally {
      done.complete();
      if (identical(_writes[subjectId], done.future)) {
        // done 已完成；这里只清理串行写入队列的引用。
        // ignore: unawaited_futures
        _writes.remove(subjectId);
      }
    }
  }

  void _requireScope(SessionScope scope) {
    if (_closed || !_api.isLoggedIn || scope != _api.sessionScope) {
      throw const ApiException('登录会话已改变，请重新打开后操作');
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _api.sessionChanges.removeListener(_resetSession);
    unawaited(_changes.close());
  }
}
