import 'package:flutter/material.dart';
import '../../core/community_models.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/network/api_client.dart';
import '../../data/bangumi_repository.dart';
import '../../domain/use_cases/comment_submit_use_case.dart';
import '../../widgets/comment_composer.dart';
import '../../widgets/common.dart';
import '../user/user_profile_page.dart';
import 'comment_page_controller.dart';
import 'community_widgets.dart';
import '../../domain/repositories/nested_comment_repository.dart';
import '../../app/state/session_scope.dart';

class CommentReadingPage<T> extends StatefulWidget {
  const CommentReadingPage({
    super.key,
    required this.repository,
    required this.title,
    required this.target,
    required this.load,
    required this.items,
    required this.onReact,
    this.header,
    this.authorUsername,
  });
  final BangumiRepository repository;
  final String title;
  final ComposeCommentTarget target;
  final Future<T> Function() load;
  final List<CommunityReply> Function(T) items;
  final Widget Function(T)? header;
  final String Function(T)? authorUsername;
  final Future<void> Function(CommunityReply, String?) onReact;
  @override
  State<CommentReadingPage<T>> createState() => _CommentReadingPageState<T>();
}

class _CommentReadingPageState<T> extends State<CommentReadingPage<T>> {
  late final _model = CommentPageController<T>(
    load: widget.load,
    session: () => CommentSubmitUseCase.currentScope(widget.repository),
  );
  final Map<(SessionScope, String), CommentEditorSession> _editors = {};
  bool _editorOpen = false;
  Listenable? get _sessionChanges =>
      widget.repository is CollectionFeatureRepository
          ? (widget.repository as CollectionFeatureRepository)
              .collections
              .sessionChanges
          : null;
  @override
  void initState() {
    super.initState();
    _sessionChanges?.addListener(_sessionChanged);
    _model.refresh();
  }

  void _sessionChanged() {
    for (final editor in _editors.values) {
      editor.invalidateSession();
    }
    _model.refresh(reset: true);
  }

  @override
  void dispose() {
    _sessionChanges?.removeListener(_sessionChanged);
    _model.dispose();
    for (final editor in _editors.values) {
      editor.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh({bool afterPublish = false}) {
    final repo = widget.repository;
    if (repo is CommentCacheRepository) {
      (repo as CommentCacheRepository).invalidateCommentReads(
        episodeId: widget.target.topic == null ? widget.target.id : null,
        topic: widget.target.topic,
      );
    }
    return _model.refresh(afterPublish: afterPublish);
  }

  Future<void> _compose([ComposeCommentReplyTarget? reply]) async {
    if (_editorOpen) return;
    final strings = AppLocalizations.of(context);
    if (!widget.repository.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.t('loginComment'))));
      return;
    }
    setState(() => _editorOpen = true);
    final target =
        reply == null
            ? widget.target
            : ComposeCommentTarget.reply(widget.target, reply);
    final key = (
      CommentSubmitUseCase.currentScope(widget.repository),
      target.key,
    );
    final editor = _editors.putIfAbsent(key, CommentEditorSession.new);
    final sent = await editor.open(context, widget.repository, target);
    if (!mounted) return;
    setState(() => _editorOpen = false);
    if (sent != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.t('published'))));
      await _refresh(afterPublish: true);
    } else if (editor.needsVerification) {
      await _refresh();
    }
  }

  void _user(String username) {
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
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final topic = widget.target.topic;
    final canPost =
        topic == null || topic.type == 'group' || topic.type == 'subject';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: strings.t('refresh'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar:
          canPost
              ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Align(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: Material(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(24),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: _editorOpen ? null : _compose,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.edit_outlined, size: 20),
                                const SizedBox(width: 10),
                                Expanded(child: Text(strings.t('commentHint'))),
                                const Icon(
                                  Icons.emoji_emotions_outlined,
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
              : null,
      body: ContentFrame(
        maxWidth: 920,
        child: ListenableBuilder(
          listenable: _model,
          builder: (context, _) {
            final state = _model.state;
            final data = state.data;
            if (data == null) {
              if (state.error != null) {
                return NetworkErrorView(error: state.error!, onRetry: _refresh);
              }
              return const LoadingView();
            }
            return Column(
              children: [
                SizedBox(
                  height: 2,
                  child:
                      state.loading
                          ? const LinearProgressIndicator(minHeight: 2)
                          : null,
                ),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        state.afterPublish
                            ? strings.t('refreshAfterPublishFailed')
                            : strings.t('retry'),
                      ),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: CommunityReplyList(
                      items: widget.items(data),
                      currentUsername: widget.repository.currentUsername,
                      authorUsername: widget.authorUsername?.call(data) ?? '',
                      header: widget.header?.call(data),
                      onUserTap: _user,
                      onReply:
                          canPost &&
                                  widget.repository
                                      is NestedCommentRepository &&
                                  !_editorOpen
                              ? (root, reply) => _compose(
                                ComposeCommentReplyTarget(
                                  root: root,
                                  reply: reply,
                                ),
                              )
                              : null,
                      onLike: (item, value) {
                        if (!widget.repository.isLoggedIn) {
                          throw ApiException(strings.t('loginComment'));
                        }
                        final scope = CommentSubmitUseCase.currentScope(
                          widget.repository,
                        );
                        return widget.onReact(item, value).then((_) {
                          if (scope !=
                              CommentSubmitUseCase.currentScope(
                                widget.repository,
                              )) {
                            throw const ApiException(
                              'commentSessionChanged',
                              outcomeUnknown: true,
                            );
                          }
                        });
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
