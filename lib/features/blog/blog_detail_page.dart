import 'package:flutter/material.dart';
import '../../widgets/liquid_glass.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/json_utils.dart';
import '../../data/bangumi_repository.dart';
import '../../domain/models/blog.dart';
import '../../domain/repositories/blog_repository.dart';
import '../../widgets/bangumi_rich_text.dart';
import '../../widgets/rich_comment_image.dart';
import '../../core/text/bbcode_document.dart';
import '../../core/models.dart';
import '../../core/network/app_image_cache.dart';
import '../../widgets/common.dart';
import '../community/comment_page_controller.dart';
import '../community/community_widgets.dart';
import '../../domain/use_cases/comment_submit_use_case.dart';
import '../subject/subject_navigation.dart';
import '../user/user_profile_page.dart';
import '../../widgets/comment_composer.dart';

class BlogDetailPage extends StatefulWidget {
  const BlogDetailPage({super.key, required this.id, required this.repository});
  final int id;
  final BangumiRepository repository;
  @override
  State<BlogDetailPage> createState() => _BlogDetailPageState();
}

class _BlogDetailPageState extends State<BlogDetailPage> {
  CommentEditorSession _editor = CommentEditorSession();
  bool _editorOpen = false;
  int _editorGeneration = 0;
  Future<void> _compose() async {
    if (_editorOpen) return;
    final s = AppLocalizations.of(context);
    if (!widget.repository.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.t('loginComment'))));
      return;
    }
    setState(() => _editorOpen = true);
    final generation = _editorGeneration;
    try {
      final sent = await _editor.open(
        context,
        widget.repository,
        ComposeCommentTarget.blog(
          widget.id,
          controller.state.data?.blog.title ?? '',
        ),
      );
      if (!mounted) return;
      if (sent != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.t('published'))));
        if (widget.repository is BlogCommentRepository) {
          (widget.repository as BlogCommentRepository).invalidateBlogComments(
            widget.id,
          );
        }
        await controller.refresh(afterPublish: true);
      }
    } finally {
      if (generation != _editorGeneration) {
        _editor.dispose();
        _editor = CommentEditorSession();
      }
      if (mounted) setState(() => _editorOpen = false);
    }
  }

  ComposeBlogDetail? _photoDetail;
  final List<ComposeBlogPhoto> _extraPhotos = [];
  bool _loadingPhotos = false;
  Object? _photoError;
  int _photoTotal = 0;
  Future<void> _morePhotos(ComposeBlogDetail detail) async {
    if (_loadingPhotos || widget.repository is! BlogPhotoRepository) return;
    final scope = CommentSubmitUseCase.currentScope(widget.repository);
    setState(() {
      _loadingPhotos = true;
      _photoError = null;
    });
    try {
      final page = await (widget.repository as BlogPhotoRepository)
          .fetchBlogPhotos(
            widget.id,
            offset: detail.photos.length + _extraPhotos.length,
          );
      if (!mounted ||
          !identical(controller.state.data, detail) ||
          scope != CommentSubmitUseCase.currentScope(widget.repository)) {
        return;
      }
      final ids =
          [...detail.photos, ..._extraPhotos].map((photo) => photo.id).toSet();
      if (page.items.any((photo) => ids.contains(photo.id))) {
        throw const FormatException('responseInvalid');
      }
      setState(() {
        _extraPhotos.addAll(page.items);
        _photoTotal = page.total ?? _photoTotal;
      });
    } on Object catch (error) {
      if (mounted &&
          identical(controller.state.data, detail) &&
          scope == CommentSubmitUseCase.currentScope(widget.repository)) {
        setState(() => _photoError = error);
      }
    } finally {
      if (mounted && identical(controller.state.data, detail)) {
        setState(() => _loadingPhotos = false);
      }
    }
  }

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
  void _sessionChanged() {
    _editor.invalidateSession();
    _editorGeneration++;
    if (!_editorOpen) {
      _editor.dispose();
      _editor = CommentEditorSession();
    }
    controller.refresh(reset: true);
  }

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
    _editor.dispose();
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: AdaptiveActionSurface(
            classicColor: Colors.transparent,
            child: OutlinedButton.icon(
              onPressed: _editorOpen ? null : _compose,
              icon: const Icon(Icons.edit_outlined),
              label: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(s.t('commentHint')),
              ),
            ),
          ),
        ),
      ),
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
          if (!identical(_photoDetail, detail)) {
            _photoDetail = detail;
            _extraPhotos.clear();
            _loadingPhotos = false;
            _photoError = null;
            _photoTotal = detail.photoTotal;
          }
          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: SelectionArea(
              child: ContentFrame(
                maxWidth: 880,
                child: CommunityReplyList(
                  items: detail.comments,
                  currentUsername: widget.repository.currentUsername,
                  authorUsername: detail.blog.user.username,
                  onUserTap: _user,
                  canReact: false,
                  showEmptySummary: !detail.errors.containsKey('comments'),
                  onLike: (_, _) async {},
                  leadingItems: blogReadingItems(
                    context,
                    detail,
                    photos: [...detail.photos, ..._extraPhotos],
                    photoFooter:
                        detail.errors.containsKey('photos')
                            ? NetworkErrorView(
                              error: detail.errors['photos']!,
                              onRetry: controller.refresh,
                            )
                            : _photoError != null
                            ? NetworkErrorView(
                              error: _photoError!,
                              onRetry: () => _morePhotos(detail),
                            )
                            : _loadingPhotos
                            ? const Center(child: CircularProgressIndicator())
                            : detail.photos.length + _extraPhotos.length <
                                _photoTotal
                            ? Center(
                              child: TextButton.icon(
                                onPressed: () => _morePhotos(detail),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: Text(s.t('blogMorePhotos')),
                              ),
                            )
                            : null,
                    onUser: _user,
                    onSubject:
                        (subject) => openSubjectDetails(
                          context,
                          subject: subject,
                          repository: widget.repository,
                          heroTag: 'blog:${widget.id}:${subject.id}',
                        ),
                  ),
                  header: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),
                        Text(
                          s.t('blogComments'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (state.error != null)
                          NetworkErrorView(
                            error: state.error!,
                            onRetry: controller.refresh,
                          ),
                        for (final error in detail.errors.entries)
                          if (error.key != 'photos')
                            NetworkErrorView(
                              error: error.value,
                              onRetry: controller.refresh,
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 日志各块由外层同一个列表按需挂载；图片不在屏外提前解码。
List<Widget> blogReadingItems(
  BuildContext context,
  ComposeBlogDetail detail, {
  required ValueChanged<String> onUser,
  required ValueChanged<Subject> onSubject,
  List<ComposeBlogPhoto>? photos,
  Widget? photoFooter,
}) {
  final s = AppLocalizations.of(context);
  final document = BangumiBbCode.parse(detail.blog.content);
  final inlineIds = <int>{};
  final inlineUrls = <String>{};
  void images(Iterable<ComposeRichTextNode> nodes) {
    for (final node in nodes) {
      if (node.tag == 'photo') {
        final uri = BangumiBbCode.photoUrl(BangumiBbCode.plain(node.children));
        if (uri != null) {
          inlineUrls.add(BangumiBbCode.canonicalImageUrl(uri));
          final id = int.tryParse(node.value);
          if (id != null) inlineIds.add(id);
        }
      } else if (node.tag == 'img') {
        final uri = BangumiBbCode.safeUrl(BangumiBbCode.plain(node.children));
        if (uri != null) inlineUrls.add(BangumiBbCode.canonicalImageUrl(uri));
      }
      images(node.children);
    }
  }

  images(document.nodes);
  Widget inset(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    child: child,
  );
  return [
    inset(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            detail.blog.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CommunityAvatar(user: detail.blog.user),
            title: Text(detail.blog.user.nickname),
            subtitle: Text(dateText(detail.blog.createdAt)),
            onTap: () => onUser(detail.blog.user.username),
          ),
          const Divider(),
        ],
      ),
    ),
    if (detail.blog.content.isEmpty) inset(Text(s.t('blogEmpty'))),
    for (final block in BangumiBbCode.blocks(document))
      inset(
        BangumiRichText(
          '',
          selectable: false,
          nodes: block,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.8),
        ),
      ),
    if (document.truncated) inset(Text(s.t('richTextLimited'))),
    for (final photo in photos ?? detail.photos)
      if (!inlineIds.contains(photo.id) &&
          !inlineUrls.contains(photo.originalUrl.toString()))
        inset(
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 720),
            child: RichCommentImage(uri: photo.originalUrl),
          ),
        ),
    if (photoFooter != null) inset(photoFooter),
    if (detail.subjects.isNotEmpty)
      inset(
        Text(
          s.t('blogSubjects'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    for (final subject in detail.subjects)
      inset(
        Card.filled(
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 48,
                height: 64,
                child:
                    subject.imageUrl.isEmpty
                        ? const Icon(Icons.movie_outlined)
                        : CachedNetworkImage(
                          imageUrl: subject.imageUrl,
                          cacheManager: AppImageCache.manager,
                          memCacheWidth: 144,
                          fit: BoxFit.cover,
                          errorWidget:
                              (_, _, _) => const Icon(Icons.movie_outlined),
                        ),
              ),
            ),
            title: Text(subject.title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onSubject(subject),
          ),
        ),
      ),
  ];
}
