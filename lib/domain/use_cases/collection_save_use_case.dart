import '../../core/network/api_client.dart';
import '../../app/state/session_scope.dart';
import '../events/collection_changed.dart';
import '../models/collection_models.dart';
import '../repositories/collection_repository.dart';
import '../repositories/user_repository.dart';

/// 跨收藏与用户统计的编排，Repository 之间不互相依赖。
class CollectionSaveUseCase {
  CollectionSaveUseCase(this.collections, this.users);
  final CollectionRepository collections;
  final UserRepository users;

  Future<CollectionChanged> call(
    int subjectId,
    CollectionPatch patch, {
    SessionScope? expectedScope,
  }) async {
    final scope = expectedScope ?? collections.sessionScope;
    if (scope != collections.sessionScope) {
      throw const ApiException('登录会话已改变，请重新打开后操作');
    }
    if (scope.username.isEmpty) throw const ApiException('请先登录后操作');
    if (!users.hasCollectionCount(scope.username)) {
      try {
        await users.fetchUser(scope.username, fresh: true);
      } on ApiException {
        // 统计不可用不阻止合法收藏；未知基线不进行猜测增减。
      }
    }
    return collections.save(subjectId, patch, scope: scope);
  }
}
