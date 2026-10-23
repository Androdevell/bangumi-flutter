import 'package:flutter/material.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/json_utils.dart';
import '../../data/bangumi_repository.dart';
import '../../domain/models/blog.dart';
import '../../domain/repositories/blog_repository.dart';
import '../../widgets/bangumi_rich_text.dart';
import '../../widgets/common.dart';
import '../community/comment_page_controller.dart';
import '../community/community_widgets.dart';
import '../../domain/use_cases/comment_submit_use_case.dart';
import '../subject/subject_navigation.dart';
import '../user/user_profile_page.dart';

class BlogDetailPage extends StatefulWidget {
  const BlogDetailPage({super.key, required this.id, required this.repository});
  final int id;
  final BangumiRepository repository;
  @override
  State<BlogDetailPage> createState() => _BlogDetailPageState();
}

class _BlogDetailPageState extends State<BlogDetailPage> {
  late final controller = CommentPageController<ComposeBlogDetail>(
    load: () => (widget.repository as BlogRepository).fetchBlog(widget.id),
    session: () => CommentSubmitUseCase.currentScope(widget.repository),
  );
  Listenable? get _sessionChanges =>
      widget.repository is CollectionFeatureRepository
          ? (widget.repository as CollectionFeatureRepository)
              .collections
              .sessionChanges
          : null;
  void _sessionChanged() => controller.refresh(reset: true);
  @override
  void initState() {
    super.initState();
    _sessionChanges?.addListener(_sessionChanged);
    controller.refresh();
  }

  @override
  void dispose() {
    _sessionChanges?.removeListener(_sessionChanged);
    controller.dispose();
    super.dispose();
  }

  void _user(String username) => Navigator.of(context).push(
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
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('blogDetail'))),
      body: ListenableBuilder(
        listenable: controller,
        builder: (_, _) {
          final state = controller.state;
          final detail = state.data;
          if (detail == null) {
            return state.error != null
                ? NetworkErrorView(
                  error: state.error!,
                  onRetry: controller.refresh,
                )
                : const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: CommunityReplyList(
              items: detail.comments,
              currentUsername: widget.repository.currentUsername,
              authorUsername: detail.blog.user.username,
              onUserTap: _user,
              canReact: false,
              showEmptySummary: !detail.errors.containsKey('comments'),
              onLike: (_, _) async {},
              header: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      detail.blog.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(detail.blog.user.nickname),
                      subtitle: Text(dateText(detail.blog.createdAt)),
                      onTap: () => _user(detail.blog.user.username),
                    ),
                    if (detail.blog.content.isEmpty)
                      Text(s.t('blogEmpty'))
                    else
                      BangumiRichText(detail.blog.content),
                    for (final subject in detail.subjects)
                      ListTile(
                        title: Text(subject.title),
                        leading: const Icon(Icons.movie_outlined),
                        onTap:
                            () => openSubjectDetails(
                              context,
                              subject: subject,
                              repository: widget.repository,
                              heroTag: 'blog:${widget.id}:${subject.id}',
                            ),
                      ),
                    if (state.error != null)
                      NetworkErrorView(
                        error: state.error!,
                        onRetry: controller.refresh,
                      ),
                    for (final error in detail.errors.entries)
                      NetworkErrorView(
                        error: error.value,
                        onRetry: controller.refresh,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
