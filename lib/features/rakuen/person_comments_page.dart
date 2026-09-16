import 'package:flutter/material.dart';

import '../../core/community_models.dart';
import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../data/bangumi_repository.dart';
import '../../widgets/common.dart';
import '../community/community_widgets.dart';
import '../user/user_profile_page.dart';

class PersonCommentsPage extends StatefulWidget {
  const PersonCommentsPage({
    super.key,
    required this.topic,
    required this.repository,
  });

  final Topic topic;
  final BangumiRepository repository;

  @override
  State<PersonCommentsPage> createState() => _PersonCommentsPageState();
}

class _PersonCommentsPageState extends State<PersonCommentsPage> {
  late Future<List<CommunityReply>> _comments = _load();

  Future<List<CommunityReply>> _load() =>
      widget.repository.fetchPersonComments(widget.topic.id);

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
    appBar: AppBar(title: Text(widget.topic.title)),
    body: FutureBuilder<List<CommunityReply>>(
      future: _comments,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return NetworkErrorView(
            error: snapshot.error!,
            onRetry: () => setState(() => _comments = _load()),
          );
        }
        if (!snapshot.hasData) {
          return const LoadingView(label: '正在加载人物讨论…');
        }
        return ContentFrame(
          maxWidth: 920,
          child: CommunityReplyList(
            items: snapshot.data!,
            currentUsername: '',
            onUserTap: _openUser,
            onLike: (_, __) => throw const ApiException('人物评论暂不支持贴贴'),
          ),
        );
      },
    ),
  );
}
