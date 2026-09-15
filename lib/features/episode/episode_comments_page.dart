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

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    return Scaffold(
      appBar: AppBar(
        title: Text('章节 ${episode.sort.toString().replaceAll('.0', '')} 评论'),
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
