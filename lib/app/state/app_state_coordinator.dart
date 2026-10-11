import 'dart:async';
import '../../domain/repositories/collection_repository.dart';
import '../../domain/repositories/user_repository.dart';

/// 同步已确认的业务变更，不承载页面或导航逻辑。
class AppStateCoordinator {
  AppStateCoordinator(CollectionRepository collections, UserRepository users) {
    _subscription = collections.changes.listen(users.applyCollectionChange);
  }
  late final StreamSubscription<Object> _subscription;

  Future<void> close() => _subscription.cancel();
}
