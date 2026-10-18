import '../../core/models.dart';
import '../../core/community_models.dart';

abstract interface class NestedCommentRepository {
  Future<void> createNestedComment({
    required int resourceId,
    Topic? topic,
    required CommunityReply root,
    required CommunityReply replyTo,
    required String content,
  });
}
