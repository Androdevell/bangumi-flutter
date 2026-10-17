import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/community_models.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/network/app_image_cache.dart';
import '../../widgets/bangumi_rich_text.dart';
import 'reaction_picker.dart';

class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({
    super.key,
    required this.user,
    this.onTap,
    this.radius = 20,
  });

  final CommunityUser user;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      backgroundImage:
          user.avatarUrl.isEmpty
              ? null
              : CachedNetworkImageProvider(
                user.avatarUrl,
                cacheManager: AppImageCache.manager,
                maxWidth:
                    (radius * 2 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
              ),
      child:
          user.avatarUrl.isEmpty
              ? const Icon(Icons.person_outline_rounded)
              : null,
    );
    return onTap == null
        ? avatar
        : Semantics(
          label:
              '${AppLocalizations.of(context).t('viewProfile')} ${user.nickname}',
          button: true,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Center(widthFactor: 1, heightFactor: 1, child: avatar),
            ),
          ),
        );
  }
}

class CommunityReplyList extends StatelessWidget {
  const CommunityReplyList({
    super.key,
    required this.items,
    required this.currentUsername,
    required this.onUserTap,
    required this.onLike,
    this.header,
    this.authorUsername = '',
    this.canReact = true,
  });

  final List<CommunityReply> items;
  final Widget? header;
  final String authorUsername;
  final bool canReact;
  final String currentUsername;
  final ValueChanged<String> onUserTap;
  final Future<void> Function(CommunityReply item, String? value) onLike;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const PageStorageKey('comments-scroll'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder:
          (context, slot) =>
              slot == 0
                  ? Column(
                    children: [
                      if (header != null) header!,
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            items.isEmpty
                                ? AppLocalizations.of(context).t('noComments')
                                : '${AppLocalizations.of(context).t('loadedComments')} · ${items.length}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ),
                    ],
                  )
                  : _ReplyTile(
                    key: ValueKey(
                      'reply:${items[slot - 1].id}:$currentUsername',
                    ),
                    item: items[slot - 1],
                    authorUsername: authorUsername,
                    canReact: canReact,
                    currentUsername: currentUsername,
                    onUserTap: onUserTap,
                    onLike: onLike,
                  ),
    );
  }
}

class _ReplyTile extends StatefulWidget {
  const _ReplyTile({
    super.key,
    required this.item,
    required this.currentUsername,
    required this.onUserTap,
    required this.onLike,
    required this.authorUsername,
    required this.canReact,
  });

  final CommunityReply item;
  final String authorUsername;
  final bool canReact;
  final String currentUsername;
  final ValueChanged<String> onUserTap;
  final Future<void> Function(CommunityReply item, String? value) onLike;

  @override
  State<_ReplyTile> createState() => _ReplyTileState();
}

class _ReplyTileState extends State<_ReplyTile> {
  late String? _selectedValue = _findSelectedValue();
  late final Map<String, int> _reactions = {
    for (final reaction in widget.item.reactions)
      reaction.value: reaction.count,
  };
  bool _busy = false;
  int _revision = 0;

  @override
  void didUpdateWidget(covariant _ReplyTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.item, widget.item) ||
        oldWidget.currentUsername != widget.currentUsername) {
      _revision++;
      _busy = false;
      _selectedValue = _findSelectedValue();
      _reactions
        ..clear()
        ..addAll({
          for (final reaction in widget.item.reactions)
            reaction.value: reaction.count,
        });
    }
  }

  String? _findSelectedValue() {
    for (final reaction in widget.item.reactions) {
      if (reaction.users.contains(widget.currentUsername)) {
        return reaction.value;
      }
    }
    return null;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final revision = _revision;
    final item = widget.item;
    final picked = await showReactionPicker(
      context,
      selectedValue: _selectedValue,
    );
    if (picked == null || !mounted || revision != _revision) return;
    final nextValue = picked.isEmpty ? null : picked;
    setState(() => _busy = true);
    try {
      await widget.onLike(item, nextValue);
      if (!mounted || revision != _revision) return;
      setState(() {
        if (_selectedValue != null) {
          _reactions[_selectedValue!] = (_reactions[_selectedValue!] ?? 1) - 1;
        }
        if (nextValue != null) {
          _reactions[nextValue] = (_reactions[nextValue] ?? 0) + 1;
        }
        _reactions.removeWhere((_, count) => count <= 0);
        _selectedValue = nextValue;
      });
    } on Object catch (error) {
      if (mounted && revision == _revision) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final strings = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CommentHeader(
            user: item.user,
            date: item.createdAt,
            currentUsername: widget.currentUsername,
            onUserTap: widget.onUserTap,
            authorUsername: widget.authorUsername,
          ),
          const SizedBox(height: 12),
          CommentBody(item.content),
          if (item.replies.isNotEmpty) ...[
            const SizedBox(height: 12),
            NestedReplyPreview(
              items: item.replies,
              onUserTap: widget.onUserTap,
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: ReactionSummary(reactions: _reactions)),
              if (widget.canReact)
                IconButton(
                  tooltip: strings.t(
                    _selectedValue == null ? 'react' : 'changeReaction',
                  ),
                  onPressed:
                      widget.currentUsername.isEmpty || _busy ? null : _toggle,
                  icon:
                      _selectedValue == null
                          ? const Icon(Icons.add_reaction_outlined, size: 20)
                          : BangumiReactionImage(
                            value: _selectedValue!,
                            size: 21,
                          ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CommentHeader extends StatelessWidget {
  const CommentHeader({
    super.key,
    required this.user,
    required this.date,
    required this.currentUsername,
    required this.onUserTap,
    this.authorUsername = '',
  });
  final CommunityUser user;
  final DateTime? date;
  final String currentUsername, authorUsername;
  final ValueChanged<String> onUserTap;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final local = date?.toLocal();
    final material = MaterialLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommunityAvatar(
          user: user,
          radius: 18,
          onTap: user.username.isEmpty ? null : () => onUserTap(user.username),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap:
                    user.username.isEmpty
                        ? null
                        : () => onUserTap(user.username),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    user.nickname,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (local != null)
                    Tooltip(
                      message: local.toString(),
                      child: Text(
                        '${material.formatCompactDate(local)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (user.username.isNotEmpty &&
                      user.username == authorUsername)
                    Text(
                      strings.t('author'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (user.username.isNotEmpty &&
                      user.username == currentUsername)
                    Text(
                      strings.t('you'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CommentBody extends StatefulWidget {
  const CommentBody(this.content, {super.key});
  final String content;
  @override
  State<CommentBody> createState() => _CommentBodyState();
}

class _CommentBodyState extends State<CommentBody> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      BangumiRichText(
        widget.content,
        maxLines: !_expanded && widget.content.length > 700 ? 10 : null,
        overflow: TextOverflow.clip,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55),
      ),
      if (widget.content.length > 700)
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Text(
            AppLocalizations.of(context).t(_expanded ? 'collapse' : 'expand'),
          ),
        ),
    ],
  );
}

class NestedReplyPreview extends StatefulWidget {
  const NestedReplyPreview({
    super.key,
    required this.items,
    required this.onUserTap,
  });
  final List<CommunityReply> items;
  final ValueChanged<String> onUserTap;
  @override
  State<NestedReplyPreview> createState() => _NestedReplyPreviewState();
}

class _NestedReplyPreviewState extends State<NestedReplyPreview> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final reply in widget.items.take(
          _expanded ? widget.items.length : 3,
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => widget.onUserTap(reply.user.username),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      reply.user.nickname,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                CommentBody(reply.content),
              ],
            ),
          ),
        if (widget.items.length > 3)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(
              AppLocalizations.of(
                context,
              ).t(_expanded ? 'collapse' : 'showReplies'),
            ),
          ),
      ],
    ),
  );
}
