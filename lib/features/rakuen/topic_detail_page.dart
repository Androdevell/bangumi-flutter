import 'package:flutter/material.dart';

import '../../core/community_models.dart';
import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../data/bangumi_repository.dart';
import '../../widgets/common.dart';
import '../community/community_widgets.dart';
import '../user/user_profile_page.dart';

class TopicDetailPage extends StatefulWidget {
  const TopicDetailPage({
    super.key,
    required this.topic,
    required this.repository,
  });

  final Topic topic;
  final BangumiRepository repository;

  @override
  State<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<TopicDetailPage> {
  late Future<TopicDetailData> _detail = _load();

  Future<TopicDetailData> _load() =>
      widget.repository.fetchTopicDetails(widget.topic);

  void _openUser(String username) {
    if (username.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => UserProfilePage(
              username: username,
              repository: widget.repository,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.topic.typeLabel)),
    body: FutureBuilder<TopicDetailData>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return NetworkErrorView(
            error: snapshot.error!,
            onRetry: () => setState(() => _detail = _load()),
          );
        }
        if (!snapshot.hasData) {
          return const LoadingView(label: '正在加载讨论…');
        }
        final detail = snapshot.data!;
        return ContentFrame(
          maxWidth: 980,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.groupName,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      detail.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        CommunityAvatar(
                          user: detail.creator,
                          radius: 16,
                          onTap: () => _openUser(detail.creator.username),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${detail.creator.nickname} · ${detail.replies.length} 条内容',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: CommunityReplyList(
                  items: detail.replies,
                  currentUsername: widget.repository.currentUsername,
                  onUserTap: _openUser,
                  onLike: (item, value) {
                    if (!widget.repository.isLoggedIn) {
                      throw const ApiException('请先登录后再贴贴');
                    }
                    return widget.repository.setTopicPostReaction(
                      detail.type,
                      item.id,
                      value,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
