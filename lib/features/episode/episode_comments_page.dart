import 'package:flutter/material.dart';

import '../../core/community_models.dart';
import '../../core/subject_detail_models.dart';
import '../../core/network/api_client.dart';
import '../../data/bangumi_repository.dart';
import '../../widgets/common.dart';
import '../community/community_widgets.dart';
import '../user/user_profile_page.dart';

class EpisodeCommentsPage extends StatefulWidget {
  const EpisodeCommentsPage({
    super.key,
    required this.episode,
    required this.repository,
  });

  final SubjectEpisode episode;
  final BangumiRepository repository;

  @override
  State<EpisodeCommentsPage> createState() => _EpisodeCommentsPageState();
}

class _EpisodeCommentsPageState extends State<EpisodeCommentsPage> {
  late Future<List<CommunityReply>> _comments = _load();
  bool _submitting = false;

  Future<List<CommunityReply>> _load() =>
      widget.repository.fetchEpisodeComments(widget.episode.id);

  void _openUser(String username) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder:
          (_) => UserProfilePage(
            username: username,
            repository: widget.repository,
          ),
    ),
  );

  Future<void> _openCommentDialog() async {
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
            title: const Text('发表章节评论'),
            content: TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              maxLength: 1000,
              decoration: const InputDecoration(
                hintText: '说说你对这一章节的看法…',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.isNotEmpty) Navigator.pop(context, value);
                },
                child: const Text('发布'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (content == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      await widget.repository.createEpisodeComment(widget.episode.id, content);
      if (!mounted) return;
      setState(() => _comments = _load());
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
  Widget build(BuildContext context) {
    final episode = widget.episode;
    return Scaffold(
      appBar: AppBar(
        title: Text('章节 ${episode.sort.toString().replaceAll('.0', '')} 评论'),
        actions: [
          IconButton(
            tooltip: '发表评论',
            onPressed: _submitting ? null : _openCommentDialog,
            icon:
                _submitting
                    ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<CommunityReply>>(
        future: _comments,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return NetworkErrorView(
              error: snapshot.error!,
              onRetry: () => setState(() => _comments = _load()),
            );
          }
          if (!snapshot.hasData) return const LoadingView(label: '正在加载章节评论…');
          return ContentFrame(
            maxWidth: 920,
            child: CommunityReplyList(
              items: snapshot.data!,
              currentUsername: widget.repository.currentUsername,
              onUserTap: _openUser,
              onLike: (item, value) {
                if (!widget.repository.isLoggedIn) {
                  throw const ApiException('请先登录后再点赞');
                }
                return widget.repository.setEpisodeCommentReaction(
                  item.id,
                  value,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
