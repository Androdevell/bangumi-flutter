import 'package:flutter/material.dart';
import '../../core/community_models.dart';
import '../../core/models.dart';
import '../../data/bangumi_repository.dart';
import '../../domain/use_cases/comment_submit_use_case.dart';
import '../community/comment_reading_page.dart';

class TopicDetailPage extends StatelessWidget {
  const TopicDetailPage({
    super.key,
    required this.topic,
    required this.repository,
  });
  final Topic topic;
  final BangumiRepository repository;
  @override
  Widget build(BuildContext context) => CommentReadingPage<TopicDetailData>(
    key: ValueKey('topic-comments:${topic.type}:${topic.id}'),
    repository: repository,
    title: topic.typeLabel,
    target: ComposeCommentTarget.topic(topic),
    load: () => repository.fetchTopicDetails(topic),
    items: (detail) => detail.replies,
    authorUsername: (detail) => detail.creator.username,
    onReact:
        (item, value) =>
            repository.setTopicPostReaction(topic.type, item.id, value),
    header:
        (detail) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.groupName,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
        ),
  );
}
