import '../../core/community_models.dart';
import '../events/collection_changed.dart';

abstract interface class UserRepository {
  Future<CommunityUser> fetchUser(String username, {bool fresh = false});
  int effectiveCollectionCount(String username, int serverCount);
  bool isCollectionCountSyncing(String username);
  bool hasCollectionCount(String username);
  void applyCollectionChange(CollectionChanged change);
}
