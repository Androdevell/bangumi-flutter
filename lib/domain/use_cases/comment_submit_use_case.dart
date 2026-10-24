import 'package:flutter/widgets.dart';
import '../../app/state/session_scope.dart';
import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../data/bangumi_repository.dart';
import '../../core/community_models.dart';
import '../repositories/nested_comment_repository.dart';
import '../repositories/blog_repository.dart';

@immutable
class ComposeCommentTarget {
  const ComposeCommentTarget.episode(this.id, this.title)
    : kind = 'episode',
      topic = null,
      replyTarget = null;
  const ComposeCommentTarget.blog(this.id, this.title)
    : kind = 'blog',
      topic = null,
      replyTarget = null;
  ComposeCommentTarget.topic(Topic value)
    : kind = 'topic',
      id = value.id,
      title = value.title,
      topic = value,
      replyTarget = null;
  ComposeCommentTarget.reply(ComposeCommentTarget target, this.replyTarget)
    : kind = target.kind,
      id = target.id,
      title = target.title,
      topic = target.topic;
  final int id;
  final String title;
  final String kind;
  final Topic? topic;
  final ComposeCommentReplyTarget? replyTarget;
  int get maxLength => kind == 'episode' ? 1000 : 2000;
  String get key =>
      '${topic?.type ?? kind}:$id:${replyTarget?.root.id ?? 0}:${replyTarget?.reply.id ?? 0}';
}

@immutable
class ComposeCommentReplyTarget {
  const ComposeCommentReplyTarget({required this.root, required this.reply});
  final CommunityReply root, reply;
}

/// 发布绑定打开编辑器时的账号会话，只调用已支持的写入路径，不自动重发。
class CommentSubmitUseCase {
  CommentSubmitUseCase(this.repository, this.target)
    : scope = currentScope(repository);
  final BangumiRepository repository;
  final ComposeCommentTarget target;
  final SessionScope scope;
  static SessionScope currentScope(BangumiRepository repository) =>
      repository is CollectionFeatureRepository
          ? (repository as CollectionFeatureRepository).collections.sessionScope
          : SessionScope(
            username: repository.currentUsername,
            accountId: 0,
            epoch: 0,
          );
  bool get isCurrent =>
      repository.isLoggedIn && currentScope(repository) == scope;
  Future<void> call(String value) async {
    if (!isCurrent) throw const ApiException('commentSessionChanged');
    if (value.trim().isEmpty || value.characters.length > target.maxLength) {
      throw const ApiException('commentInvalid');
    }
    final topic = target.topic;
    if (topic != null && topic.type != 'group' && topic.type != 'subject') {
      throw const ApiException('commentInvalid');
    }
    final reply = target.replyTarget;
    if (target.kind == 'blog') {
      if (repository is! BlogCommentRepository) {
        throw const ApiException('commentInvalid');
      }
      await (repository as BlogCommentRepository).createBlogComment(
        target.id,
        value.trim(),
        scope: scope,
        replyTo: reply?.reply.id ?? 0,
      );
    } else if (reply != null) {
      final repo = repository;
      if (repo is! NestedCommentRepository) {
        throw const ApiException('commentInvalid');
      }
      await (repo as NestedCommentRepository).createNestedComment(
        resourceId: target.id,
        topic: topic,
        root: reply.root,
        replyTo: reply.reply,
        content: value.trim(),
      );
    } else if (topic == null) {
      await repository.createEpisodeComment(target.id, value.trim());
    } else {
      await repository.createTopicReply(topic, value.trim());
    }
    if (!isCurrent) {
      throw const ApiException('commentSessionChanged', outcomeUnknown: true);
    }
  }
}
