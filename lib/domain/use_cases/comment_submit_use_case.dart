import 'package:flutter/widgets.dart';
import '../../app/state/session_scope.dart';
import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../data/bangumi_repository.dart';

@immutable
class ComposeCommentTarget {
  const ComposeCommentTarget.episode(this.id, this.title) : topic = null;
  ComposeCommentTarget.topic(Topic value)
    : id = value.id,
      title = value.title,
      topic = value;
  final int id;
  final String title;
  final Topic? topic;
  int get maxLength => topic == null ? 1000 : 2000;
  String get key => '${topic?.type ?? 'episode'}:$id';
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
    if (topic == null) {
      await repository.createEpisodeComment(target.id, value.trim());
    } else {
      await repository.createTopicReply(topic, value.trim());
    }
    if (!isCurrent) {
      throw const ApiException('commentSessionChanged', outcomeUnknown: true);
    }
  }
}
