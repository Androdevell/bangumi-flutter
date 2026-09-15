import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/network/app_image_cache.dart';
import '../../core/subject_detail_models.dart';
import '../../data/bangumi_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/subject_card.dart';
import '../character/character_detail_page.dart';
import '../community/reaction_picker.dart';
import '../episode/episode_comments_page.dart';
import '../user/user_profile_page.dart';

class SubjectDetailPage extends StatefulWidget {
  const SubjectDetailPage({
    super.key,
    required this.subject,
    required this.heroTag,
    required this.repository,
  });

  final Subject subject;
  final String heroTag;
  final BangumiRepository repository;

  @override
  State<SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends State<SubjectDetailPage> {
  static const _tabNames = [
    '章节',
    '简介',
    '预览',
    '吐槽',
    '角色',
    '制作人员',
    '关联',
    '目录',
    '日志',
    '话题',
    '透视',
  ];

  late Future<SubjectDetailData> _details = _load();
  int? _interestType;

  Future<SubjectDetailData> _load() =>
      widget.repository.fetchSubjectDetails(widget.subject.id);

  void _retry() {
    setState(() => _details = _load());
  }

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

  Future<void> _editCollection(SubjectDetailData details) async {
    if (!widget.repository.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录后再收藏条目')));
      return;
    }
    var type = _interestType ?? details.interestType;
    if (type == 0) type = 1;
    var rate = details.interestRate;
    var comment = details.interestComment;
    var isPrivate = details.interestPrivate;
    const statuses = [
      (1, '想看', Icons.bookmark_add_outlined),
      (2, '看过', Icons.done_all_rounded),
      (3, '在看', Icons.play_circle_outline_rounded),
      (4, '搁置', Icons.pause_circle_outline_rounded),
      (5, '抛弃', Icons.block_outlined),
    ];
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => Padding(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    0,
                    22,
                    MediaQuery.viewInsetsOf(context).bottom + 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '收藏与评价',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            details.subject.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '收藏状态',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 9),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final status in statuses)
                                ChoiceChip(
                                  avatar: Icon(status.$3, size: 17),
                                  label: Text(status.$2),
                                  selected: type == status.$1,
                                  onSelected:
                                      (_) => setDialogState(
                                        () => type = status.$1,
                                      ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Text(
                                '评分',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const Spacer(),
                              Text(rate == 0 ? '未评分' : '$rate / 10'),
                            ],
                          ),
                          Slider(
                            value: rate.toDouble(),
                            min: 0,
                            max: 10,
                            divisions: 10,
                            label: rate == 0 ? '未评分' : '$rate 分',
                            onChanged:
                                (value) =>
                                    setDialogState(() => rate = value.round()),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              for (var value = 2; value <= 10; value += 2)
                                Text(
                                  '$value',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            initialValue: comment,
                            maxLines: 4,
                            maxLength: 200,
                            decoration: const InputDecoration(
                              labelText: '简评',
                              hintText: '写下此刻的感受',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) => comment = value,
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: Icon(
                              isPrivate
                                  ? Icons.lock_outline_rounded
                                  : Icons.public_rounded,
                            ),
                            title: const Text('仅自己可见'),
                            subtitle: Text(
                              isPrivate ? '不会展示在公开收藏中' : '其他用户可查看这条收藏',
                            ),
                            value: isPrivate,
                            onChanged:
                                (value) =>
                                    setDialogState(() => isPrivate = value),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed:
                                  () => Navigator.pop(dialogContext, true),
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('保存收藏'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ),
    );
    if (saved != true || !mounted) return;
    try {
      await widget.repository.updateSubjectCollection(
        details.subject.id,
        type: type,
        rate: rate,
        comment: comment,
        isPrivate: isPrivate,
      );
      if (!mounted) return;
      setState(() => _interestType = type);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('收藏已更新')));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SubjectDetailData>(
      future: _details,
      builder: (context, snapshot) {
        final details = snapshot.data;
        final subject = details?.subject ?? widget.subject;
        return DefaultTabController(
          length: _tabNames.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(subject.title),
              actions: [
                if (details != null)
                  IconButton(
                    tooltip: '收藏与评价',
                    onPressed: () => _editCollection(details),
                    icon: Icon(
                      (_interestType ?? details.interestType) > 0
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                    ),
                  ),
              ],
            ),
            body: SafeArea(
              child: ContentFrame(
                maxWidth: 1200,
                child: Column(
                  children: [
                    _SubjectHeader(subject: subject, heroTag: widget.heroTag),
                    Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [for (final name in _tabNames) Tab(text: name)],
                      ),
                    ),
                    Expanded(
                      child:
                          snapshot.hasError
                              ? NetworkErrorView(
                                error: snapshot.error!,
                                onRetry: _retry,
                              )
                              : details == null
                              ? const LoadingView(label: '正在加载条目资料…')
                              : TabBarView(
                                children: [
                                  _EpisodeSection(
                                    items: details.episodes,
                                    repository: widget.repository,
                                  ),
                                  _SummarySection(details: details),
                                  _PreviewSection(items: details.previews),
                                  _CommentSection(
                                    items: details.comments,
                                    repository: widget.repository,
                                    onUserTap: _openUser,
                                  ),
                                  _CharacterSection(
                                    items: details.characters,
                                    repository: widget.repository,
                                  ),
                                  _StaffSection(items: details.staffs),
                                  _RelationSection(
                                    items: details.relations,
                                    repository: widget.repository,
                                    parentSubjectId: subject.id,
                                  ),
                                  _IndexSection(
                                    items: details.indexes,
                                    onUserTap: _openUser,
                                  ),
                                  _ReviewSection(
                                    items: details.reviews,
                                    onUserTap: _openUser,
                                  ),
                                  _TopicSection(
                                    items: details.topics,
                                    onUserTap: _openUser,
                                  ),
                                  _InsightSection(details: details),
                                ],
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SubjectHeader extends StatelessWidget {
  const _SubjectHeader({required this.subject, required this.heroTag});

  final Subject subject;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final posterWidth = compact ? 88.0 : 116.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 24,
            compact ? 10 : 18,
            compact ? 12 : 24,
            compact ? 12 : 18,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: posterWidth,
                height: posterWidth * 1.4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Hero(tag: heroTag, child: PosterArt(subject: subject)),
                ),
              ),
              SizedBox(width: compact ? 14 : 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.title,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style:
                          compact
                              ? Theme.of(context).textTheme.titleLarge
                              : Theme.of(context).textTheme.headlineMedium,
                    ),
                    if (subject.originalTitle.isNotEmpty &&
                        subject.originalTitle != subject.title) ...[
                      const SizedBox(height: 3),
                      Text(
                        subject.originalTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      [
                        subject.typeLabel,
                        if (subject.episodes > 0) '全 ${subject.episodes} 话',
                        if (subject.airDate.isNotEmpty) subject.airDate,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _HeaderMetric(
                          icon: Icons.star_rounded,
                          color: Colors.amber.shade700,
                          text:
                              subject.score > 0
                                  ? '${subject.score.toStringAsFixed(1)}  ${subject.ratingCount} 人'
                                  : '暂无评分',
                        ),
                        if (subject.rank > 0)
                          _HeaderMetric(
                            icon: Icons.leaderboard_outlined,
                            text: '排名 #${subject.rank}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 5),
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _EpisodeSection extends StatelessWidget {
  const _EpisodeSection({required this.items, required this.repository});

  final List<SubjectEpisode> items;
  final BangumiRepository repository;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyView(message: '暂无章节数据');
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        final number =
            item.sort % 1 == 0
                ? item.sort.toInt().toString()
                : item.sort.toString();
        final secondary = [
          if (item.name.isNotEmpty && item.name != item.title) item.name,
          item.airdate,
          item.duration,
        ].where((value) => value.isNotEmpty).join(' · ');
        return ListTile(
          leading: SizedBox(
            width: 42,
            child: Text(
              number,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          title: Text(item.title),
          subtitle: secondary.isEmpty ? null : Text(secondary),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '查看评论',
                onPressed:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder:
                            (_) => EpisodeCommentsPage(
                              episode: item,
                              repository: repository,
                            ),
                      ),
                    ),
                icon: Badge(
                  isLabelVisible: item.commentCount > 0,
                  label: Text('${item.commentCount}'),
                  child: const Icon(Icons.forum_outlined),
                ),
              ),
              PopupMenuButton<int>(
                tooltip: '更新进度',
                enabled: repository.isLoggedIn,
                onSelected: (value) async {
                  try {
                    await repository.updateEpisodeProgress(
                      item.id,
                      value,
                      batch: value == 2,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('章节进度已更新')));
                    }
                  } on Object catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$error')));
                    }
                  }
                },
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(value: 1, child: Text('想看')),
                      PopupMenuItem(value: 2, child: Text('看到这里')),
                      PopupMenuItem(value: 3, child: Text('抛弃')),
                      PopupMenuItem(value: 0, child: Text('撤销进度')),
                    ],
              ),
            ],
          ),
          onTap:
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder:
                      (_) => EpisodeCommentsPage(
                        episode: item,
                        repository: repository,
                      ),
                ),
              ),
        );
      },
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.details});

  final SubjectDetailData details;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle(title: '简介', icon: Icons.notes_rounded),
        const SizedBox(height: 8),
        SelectableText(
          details.subject.summary.isEmpty ? '暂无简介' : details.subject.summary,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (details.tags.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionTitle(title: '标签', icon: Icons.sell_outlined),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final tag in details.tags.take(30))
                Chip(label: Text('${tag.name} ${tag.count}')),
            ],
          ),
        ],
        if (details.infobox.any((field) => field.values.isNotEmpty)) ...[
          const SizedBox(height: 24),
          _SectionTitle(title: '条目信息', icon: Icons.info_outline_rounded),
          const SizedBox(height: 8),
          SurfaceBlock(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final field in details.infobox.where(
                  (item) => item.values.isNotEmpty,
                ))
                  _InfoRow(label: field.key, value: field.values.join('、')),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({required this.items});

  final List<SubjectPreview> items;

  static const _imageHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
        'Chrome/131.0 Mobile Safari/537.36',
    'Referer': 'https://movie.douban.com/',
  };

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyView(message: '暂无预览图片');
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.55,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            onTap:
                () => showDialog<void>(
                  context: context,
                  builder:
                      (context) => Dialog.fullscreen(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 5,
                              child: _NetworkArtwork(
                                imageUrl: item.largeImageUrl,
                                fallbackImageUrl: item.imageUrl,
                                fit: BoxFit.contain,
                                fallbackIcon:
                                    Icons.image_not_supported_outlined,
                                httpHeaders: _imageHeaders,
                              ),
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: SafeArea(
                                child: IconButton.filledTonal(
                                  tooltip: '关闭',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ),
            child: _NetworkArtwork(
              imageUrl: item.imageUrl,
              fallbackImageUrl: item.largeImageUrl,
              fit: BoxFit.cover,
              fallbackIcon: Icons.image_not_supported_outlined,
              httpHeaders: _imageHeaders,
            ),
          ),
        );
      },
    );
  }
}

class _CommentSection extends StatelessWidget {
  const _CommentSection({
    required this.items,
    required this.repository,
    required this.onUserTap,
  });

  final List<SubjectComment> items;
  final BangumiRepository repository;
  final ValueChanged<String> onUserTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyView(message: '暂无吐槽');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder:
          (context, index) => _SubjectCommentTile(
            item: items[index],
            repository: repository,
            onUserTap: onUserTap,
          ),
    );
  }
}

class _SubjectCommentTile extends StatefulWidget {
  const _SubjectCommentTile({
    required this.item,
    required this.repository,
    required this.onUserTap,
  });

  final SubjectComment item;
  final BangumiRepository repository;
  final ValueChanged<String> onUserTap;

  @override
  State<_SubjectCommentTile> createState() => _SubjectCommentTileState();
}

class _SubjectCommentTileState extends State<_SubjectCommentTile> {
  late String? _selectedValue = widget.item.reactionBy(
    widget.repository.currentUsername,
  );
  late final Map<String, int> _reactions = Map.of(widget.item.reactions);
  bool _busy = false;

  Future<void> _toggleLike() async {
    if (_busy || !widget.repository.isLoggedIn) return;
    final picked = await showReactionPicker(
      context,
      selectedValue: _selectedValue,
    );
    if (picked == null || !mounted) return;
    final nextValue = picked.isEmpty ? null : picked;
    setState(() => _busy = true);
    try {
      await widget.repository.setSubjectCommentReaction(
        widget.item.id,
        nextValue,
      );
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
    return SurfaceBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(
                imageUrl: item.avatarUrl,
                name: item.userName,
                onTap: () => widget.onUserTap(item.username),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      _dateText(item.updatedAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (item.rate > 0) ...[
                Icon(
                  Icons.star_rounded,
                  size: 17,
                  color: Colors.amber.shade700,
                ),
                const SizedBox(width: 3),
                Text('${item.rate}'),
              ],
              IconButton(
                tooltip: _selectedValue == null ? '贴贴' : '更换表情',
                onPressed:
                    !widget.repository.isLoggedIn || _busy ? null : _toggleLike,
                icon:
                    _selectedValue == null
                        ? const Icon(Icons.add_reaction_outlined)
                        : Text(
                          reactionEmoji(_selectedValue!),
                          style: const TextStyle(fontSize: 20),
                        ),
              ),
            ],
          ),
          if (item.comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(item.comment),
          ],
          if (_reactions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ReactionSummary(reactions: _reactions),
          ],
        ],
      ),
    );
  }
}

class _CharacterSection extends StatelessWidget {
  const _CharacterSection({required this.items, required this.repository});

  final List<SubjectCharacter> items;
  final BangumiRepository repository;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyView(message: '暂无角色资料');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 7,
          ),
          leading: _SquareArtwork(
            imageUrl: item.imageUrl,
            icon: Icons.person_outline_rounded,
            alignment: Alignment.topCenter,
          ),
          title: Text(item.name),
          subtitle: Text(
            [
              item.role,
              if (item.casts.isNotEmpty) '声优：${item.casts.join('、')}',
              item.info,
            ].where((value) => value.isNotEmpty).join('\n'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap:
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder:
                      (_) => CharacterDetailPage(
                        characterId: item.id,
                        repository: repository,
                      ),
                ),
              ),
        );
      },
    );
  }
}

class _StaffSection extends StatelessWidget {
  const _StaffSection({required this.items});

  final List<SubjectStaff> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyView(message: '暂无制作人员资料');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 7,
          ),
          leading: _SquareArtwork(
            imageUrl: item.imageUrl,
            icon: Icons.badge_outlined,
          ),
          title: Text(item.name),
          subtitle: Text(
            [
              item.positions.join('、'),
              item.info,
            ].where((value) => value.isNotEmpty).join('\n'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

class _RelationSection extends StatelessWidget {
  const _RelationSection({
    required this.items,
    required this.repository,
    required this.parentSubjectId,
  });

  final List<SubjectRelation> items;
  final BangumiRepository repository;
  final int parentSubjectId;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyView(message: '暂无关联条目');
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 390,
        mainAxisExtent: 116,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final heroTag = 'relation-$parentSubjectId-${item.subject.id}-$index';
        return SurfaceBlock(
          padding: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder:
                        (_) => SubjectDetailPage(
                          subject: item.subject,
                          heroTag: heroTag,
                          repository: repository,
                        ),
                  ),
                ),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Row(
                children: [
                  SizedBox(
                    width: 66,
                    height: 94,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Hero(
                        tag: heroTag,
                        child: PosterArt(subject: item.subject),
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.subject.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          [item.relation, item.subject.typeLabel].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.subject.score > 0)
                          Text('评分 ${item.subject.score.toStringAsFixed(1)}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IndexSection extends StatelessWidget {
  const _IndexSection({required this.items, required this.onUserTap});

  final List<SubjectIndex> items;
  final ValueChanged<String> onUserTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyView(message: '暂无关联目录');
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          leading: _Avatar(
            imageUrl: item.avatarUrl,
            name: item.userName,
            onTap: () => onUserTap(item.username),
          ),
          title: Text(item.title),
          subtitle: Text('${item.userName} · ${_dateText(item.updatedAt)}'),
          trailing: Text('${item.total} 项'),
        );
      },
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.items, required this.onUserTap});

  final List<SubjectReview> items;
  final ValueChanged<String> onUserTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyView(message: '暂无日志');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return SurfaceBlock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(
                    imageUrl: item.avatarUrl,
                    name: item.userName,
                    onTap: () => onUserTap(item.username),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('${item.userName} · ${_dateText(item.updatedAt)}'),
                      ],
                    ),
                  ),
                  _CountLabel(icon: Icons.forum_outlined, count: item.replies),
                ],
              ),
              if (item.summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  item.summary,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TopicSection extends StatelessWidget {
  const _TopicSection({required this.items, required this.onUserTap});

  final List<SubjectTopic> items;
  final ValueChanged<String> onUserTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyView(message: '暂无话题');
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          leading: _Avatar(
            imageUrl: item.avatarUrl,
            name: item.userName,
            onTap: () => onUserTap(item.username),
          ),
          title: Text(item.title),
          subtitle: Text('${item.userName} · ${_dateText(item.updatedAt)}'),
          trailing: _CountLabel(
            icon: Icons.forum_outlined,
            count: item.replies,
          ),
        );
      },
    );
  }
}

class _InsightSection extends StatelessWidget {
  const _InsightSection({required this.details});

  final SubjectDetailData details;

  static const _collectionLabels = {
    1: '想看',
    2: '看过',
    3: '在看',
    4: '搁置',
    5: '抛弃',
  };

  @override
  Widget build(BuildContext context) {
    final ratings = details.ratingDistribution;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle(title: '评分分布', icon: Icons.bar_chart_rounded),
        const SizedBox(height: 12),
        if (ratings.isEmpty)
          const Text('暂无评分分布')
        else
          for (var score = 10; score >= 1; score--)
            _StatBar(
              label: '$score',
              value: score <= ratings.length ? ratings[score - 1] : 0,
              max: ratings.fold<int>(
                0,
                (max, value) => value > max ? value : max,
              ),
            ),
        const SizedBox(height: 26),
        _SectionTitle(title: '收藏状态', icon: Icons.people_alt_outlined),
        const SizedBox(height: 12),
        if (details.collectionCounts.isEmpty)
          const Text('暂无收藏统计')
        else
          for (final entry in _collectionLabels.entries)
            _StatBar(
              label: entry.value,
              value: details.collectionCounts[entry.key] ?? 0,
              max: details.collectionCounts.values.fold<int>(
                0,
                (max, value) => value > max ? value : max,
              ),
            ),
      ],
    );
  }
}

class _StatBar extends StatelessWidget {
  const _StatBar({required this.label, required this.value, required this.max});

  final String label;
  final int value;
  final int max;

  @override
  Widget build(BuildContext context) {
    final fraction = max == 0 ? 0.0 : value / max;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 42, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 12,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 58, child: Text('$value', textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          ),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 7),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _SquareArtwork extends StatelessWidget {
  const _SquareArtwork({
    required this.imageUrl,
    required this.icon,
    this.alignment = Alignment.center,
  });

  final String imageUrl;
  final IconData icon;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: _NetworkArtwork(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          fallbackIcon: icon,
          alignment: alignment,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.imageUrl, required this.name, this.onTap});

  final String imageUrl;
  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = SizedBox(
      width: 38,
      height: 38,
      child: ClipOval(
        child: _NetworkArtwork(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          fallbackIcon: Icons.person_outline_rounded,
        ),
      ),
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

class _NetworkArtwork extends StatelessWidget {
  const _NetworkArtwork({
    required this.imageUrl,
    required this.fit,
    required this.fallbackIcon,
    this.alignment = Alignment.center,
    this.httpHeaders,
    this.fallbackImageUrl = '',
  });

  final String imageUrl;
  final BoxFit fit;
  final IconData fallbackIcon;
  final Alignment alignment;
  final Map<String, String>? httpHeaders;
  final String fallbackImageUrl;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Center(child: Icon(fallbackIcon)),
    );
    if (imageUrl.isEmpty) return fallback;
    final alternate =
        fallbackImageUrl.isEmpty || fallbackImageUrl == imageUrl
            ? fallback
            : CachedNetworkImage(
              imageUrl: fallbackImageUrl,
              cacheManager: AppImageCache.manager,
              fit: fit,
              alignment: alignment,
              httpHeaders: httpHeaders,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholderFadeInDuration: Duration.zero,
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback,
            );
    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheManager: AppImageCache.manager,
      fit: fit,
      alignment: alignment,
      httpHeaders: httpHeaders,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => alternate,
    );
  }
}

class _CountLabel extends StatelessWidget {
  const _CountLabel({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text('$count'),
      ],
    );
  }
}

String _dateText(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
