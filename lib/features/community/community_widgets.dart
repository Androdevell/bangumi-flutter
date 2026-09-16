import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/community_models.dart';
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
                maxWidth: (radius * 4).round(),
              ),
      child:
          user.avatarUrl.isEmpty
              ? const Icon(Icons.person_outline_rounded)
              : null,
    );
    return onTap == null
        ? avatar
        : InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: avatar,
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
  });

  final List<CommunityReply> items;
  final String currentUsername;
  final ValueChanged<String> onUserTap;
  final Future<void> Function(CommunityReply item, String? value) onLike;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('暂无评论'));
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder:
          (context, index) => _ReplyTile(
            item: items[index],
            currentUsername: currentUsername,
            onUserTap: onUserTap,
            onLike: onLike,
          ),
    );
  }
}

class _ReplyTile extends StatefulWidget {
  const _ReplyTile({
    required this.item,
    required this.currentUsername,
    required this.onUserTap,
    required this.onLike,
  });

  final CommunityReply item;
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
    final picked = await showReactionPicker(
      context,
      selectedValue: _selectedValue,
    );
    if (picked == null || !mounted) return;
    final nextValue = picked.isEmpty ? null : picked;
    setState(() => _busy = true);
    try {
      await widget.onLike(widget.item, nextValue);
      if (!mounted) return;
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommunityAvatar(
            user: item.user,
            onTap:
                item.user.username.isEmpty
                    ? null
                    : () => widget.onUserTap(item.user.username),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.user.nickname,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                BangumiRichText(item.content),
                if (item.replies.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final reply in item.replies)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: BangumiRichText(
                              '${reply.user.nickname}：${reply.content}',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (_reactions.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  ReactionSummary(reactions: _reactions),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: _selectedValue == null ? '贴贴' : '更换表情',
            onPressed: widget.currentUsername.isEmpty || _busy ? null : _toggle,
            icon:
                _selectedValue == null
                    ? const Icon(Icons.add_reaction_outlined)
                    : BangumiReactionImage(value: _selectedValue!, size: 21),
          ),
        ],
      ),
    );
  }
}
