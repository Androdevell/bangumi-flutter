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
  bool _submitting = false;

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

  Future<void> _openReplyDialog() async {
    if (!widget.repository.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录后再发表评论')));
      return;
    }
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            icon: const Icon(Icons.add_comment_outlined),
            title: const Text('发表评论'),
            content: SizedBox(
              width: 520,
              child: TextField(
                controller: controller,
                autofocus: true,
                minLines: 4,
                maxLines: 10,
                maxLength: 2000,
                decoration: const InputDecoration(
                  hintText: '参与讨论，写下你的看法…',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.isNotEmpty) Navigator.pop(context, value);
                },
                icon: const Icon(Icons.send_rounded),
                label: const Text('发布'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (content == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      await widget.repository.createTopicReply(widget.topic, content);
      if (!mounted) return;
      setState(() => _detail = _load());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('评论已发布')));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.topic.typeLabel),
      actions: [
        IconButton.filledTonal(
          tooltip: '发表评论',
          onPressed: _submitting ? null : _openReplyDialog,
          icon:
              _submitting
                  ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.add_comment_outlined),
        ),
        const SizedBox(width: 10),
      ],
    ),
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
