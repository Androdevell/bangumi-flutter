import '../../core/community_models.dart';
import '../../core/network/api_client.dart';
import '../../domain/events/collection_changed.dart';
import '../../domain/repositories/user_repository.dart';

class RemoteUserRepository implements UserRepository {
  RemoteUserRepository(this._api) {
    _api.sessionChanges.addListener(_clearSession);
  }
  final ApiClient _api;
  final Map<String, _CollectionStatistics> _counts = {};
  bool _closed = false;

  void _clearSession() => _counts.clear();

  @override
  Future<CommunityUser> fetchUser(String username, {bool fresh = false}) async {
    final scope = _api.sessionScope;
    final count = _counts.putIfAbsent(username, _CollectionStatistics.new);
    final revision = count.revision;
    final result = await _api.get(
      'p1/users/${Uri.encodeComponent(username)}',
      fresh: fresh,
    );
    if (_closed || scope != _api.sessionScope) {
      throw const ApiException('登录会话已改变，请重新加载');
    }
    if (result is! Map ||
        result['stats'] is! Map ||
        (result['stats'] as Map)['subject'] is! Map) {
      throw const ApiException('用户统计格式不正确');
    }
    final user = CommunityUser.fromJson(Map<String, dynamic>.from(result));
    if (count.revision == revision) count.reconcile(user.stats.subjects);
    return user;
  }

  @override
  int effectiveCollectionCount(String username, int serverCount) {
    final count = _counts.putIfAbsent(username, _CollectionStatistics.new);
    count.baseline ??= serverCount;
    return count.expected ?? serverCount;
  }

  @override
  bool isCollectionCountSyncing(String username) =>
      _counts[username]?.syncing ?? false;

  @override
  bool hasCollectionCount(String username) =>
      _counts[username]?.baseline != null;

  @override
  void applyCollectionChange(CollectionChanged change) {
    if (_closed || change.session != _api.sessionScope) return;
    final count = _counts.putIfAbsent(
      change.session.username,
      _CollectionStatistics.new,
    );
    if (change.revision <= count.revision) return;
    count.revision = change.revision;
    if (change.previousStatus == 0 && change.nextStatus > 0) {
      count.delta++;
      count.syncing = true;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _api.sessionChanges.removeListener(_clearSession);
    _clearSession();
  }
}

class _CollectionStatistics {
  int? baseline;
  int delta = 0;
  int revision = 0;
  bool syncing = false;
  int? get expected => baseline == null ? null : baseline! + delta;

  void reconcile(int server) {
    if (baseline == null || delta == 0 || server == expected) {
      baseline = server;
      delta = 0;
      syncing = false;
    }
  }
}
