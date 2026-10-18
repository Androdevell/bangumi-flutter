import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/models.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/network/app_image_cache.dart';
import '../../data/bangumi_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/bangumi_rich_text.dart';
import '../community/reaction_picker.dart';
import '../subject/subject_detail_page.dart';
import '../user/user_profile_page.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({
    super.key,
    required this.repository,
    this.sessionRevision = 0,
  });
  final int sessionRevision;

  final BangumiRepository repository;

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  int _filter = 0;
  late Future<List<TimelineEntry>> _entries = _load();

  @override
  void didUpdateWidget(covariant TimelinePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionRevision != widget.sessionRevision ||
        oldWidget.repository != widget.repository) {
      if (!widget.repository.isLoggedIn && _filter == 1) _filter = 0;
      _entries = _load();
    }
  }

  Future<List<TimelineEntry>> _load() => widget.repository.fetchTimeline(
    mode: _filter == 1 ? 'friends' : 'all',
    category: _filter == 2 ? 5 : null,
  );

  Future<void> _reload() async {
    invalidateRepositoryCache(widget.repository);
    final future = _load();
    setState(() {
      _entries = future;
    });
    try {
      await future;
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  void _select(int value) {
    if (value == _filter) return;
    setState(() {
      _filter = value;
      _entries = _load();
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ContentFrame(
      maxWidth: 940,
      child: FutureBuilder<List<TimelineEntry>>(
        future: _entries,
        builder: (context, snapshot) {
          final entries = snapshot.data ?? const <TimelineEntry>[];
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              key: const PageStorageKey('timeline-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
              children: [
                PageHeader(
                  title: AppStrings.timeline,
                  subtitle: '收藏、进度、吐槽与社区动态',
                  actions: [
                    IconButton.filledTonal(
                      tooltip: '刷新',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<int>(
                    segments: [
                      const ButtonSegment(
                        value: 0,
                        label: Text('全部'),
                        icon: Icon(Icons.public_rounded),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: const Text('好友'),
                        icon: const Icon(Icons.people_outline_rounded),
                        enabled: widget.repository.isLoggedIn,
                      ),
                      const ButtonSegment(
                        value: 2,
                        label: Text('吐槽'),
                        icon: Icon(Icons.chat_bubble_outline_rounded),
                      ),
                    ],
                    selected: {_filter},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) => _select(value.first),
                  ),
                ),
                const SizedBox(height: 18),
                if (_filter == 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      AppLocalizations.of(context).t('timelineLocalFilterHint'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (snapshot.connectionState != ConnectionState.done &&
                    entries.isEmpty)
                  const LoadingView()
                else if (snapshot.hasError && entries.isEmpty)
                  NetworkErrorView(error: snapshot.error!, onRetry: _reload)
                else if (entries.isEmpty)
                  EmptyView(message: _filter == 1 ? '登录后可查看好友动态' : '暂无动态')
                else
                  ..._buildGroupedEntries(entries),
              ],
            ),
          );
        },
      ),
    ),
  );

  List<Widget> _buildGroupedEntries(List<TimelineEntry> entries) {
    final widgets = <Widget>[];
    String? lastDate;
    for (final entry in entries) {
      final date = _dateLabel(entry.createdAt);
      if (date != lastDate) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 12));
        widgets.add(_DateHeader(label: date));
        widgets.add(const SizedBox(height: 8));
        lastDate = date;
      }
      widgets.add(
        _TimelineTile(
          key: ValueKey(
            'timeline:${entry.id}:${widget.repository.currentUsername}',
          ),
          entry: entry,
          repository: widget.repository,
        ),
      );
    }
    return widgets;
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 9),
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(width: 12),
      const Expanded(child: Divider()),
    ],
  );
}

class _TimelineTile extends StatefulWidget {
  const _TimelineTile({
    super.key,
    required this.entry,
    required this.repository,
  });
  final TimelineEntry entry;
  final BangumiRepository repository;

  @override
  State<_TimelineTile> createState() => _TimelineTileState();
}

class _TimelineTileState extends State<_TimelineTile> {
  late String? _selectedValue = widget.entry.reactionBy(
    widget.repository.currentUsername,
  );
  late final Map<String, int> _reactions = Map.of(widget.entry.reactions);
  bool _busy = false;
  int _revision = 0;

  @override
  void didUpdateWidget(covariant _TimelineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry != widget.entry) {
      _revision++;
      _selectedValue = widget.entry.reactionBy(
        widget.repository.currentUsername,
      );
      _reactions
        ..clear()
        ..addAll(widget.entry.reactions);
    }
  }

  Future<void> _react() async {
    if (!widget.repository.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录后再贴贴')));
      return;
    }
    if (_busy) return;
    final revision = _revision;
    final entry = widget.entry;
    setState(() => _busy = true);
    try {
      final picked = await showReactionPicker(
        context,
        selectedValue: _selectedValue,
      );
      if (picked == null || !mounted || revision != _revision) return;
      final nextValue = picked.isEmpty ? null : picked;
      await widget.repository.setTimelineReaction(entry.id, nextValue);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openUser() {
    if (widget.entry.username.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => UserProfilePage(
              username: widget.entry.username,
              repository: widget.repository,
            ),
      ),
    );
  }

  void _openSubject() {
    final entry = widget.entry;
    if (entry.subjectId <= 0) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => SubjectDetailPage(
              subject: Subject(
                id: entry.subjectId,
                title: entry.subject,
                imageUrl: entry.imageUrl,
              ),
              heroTag: 'timeline-${entry.id}-${entry.subjectId}',
              repository: widget.repository,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder:
          (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - value)),
              child: child,
            ),
          ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _openUser,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: entry.color.withValues(alpha: 0.18),
                    foregroundColor: entry.color,
                    backgroundImage:
                        entry.avatarUrl.isEmpty
                            ? null
                            : CachedNetworkImageProvider(
                              entry.avatarUrl,
                              cacheManager: AppImageCache.manager,
                              maxWidth: 160,
                            ),
                    child:
                        entry.avatarUrl.isEmpty
                            ? Text(
                              entry.user.isEmpty
                                  ? '?'
                                  : entry.user.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            )
                            : null,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: entry.username.isEmpty ? null : _openUser,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Text(
                                  entry.user,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleSmall?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Text(
                            [
                              entry.relativeTime(),
                              entry.sourceName,
                            ].where((text) => text.isNotEmpty).join(' · '),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.action,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (entry.subjectId > 0 ||
                          entry.imageUrl.isNotEmpty ||
                          entry.detail.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Material(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: entry.subjectId > 0 ? _openSubject : null,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 52,
                                      height: 70,
                                      child:
                                          entry.imageUrl.isEmpty
                                              ? ColoredBox(
                                                color:
                                                    scheme.secondaryContainer,
                                                child: Icon(
                                                  Icons.movie_filter_outlined,
                                                  color:
                                                      scheme
                                                          .onSecondaryContainer,
                                                ),
                                              )
                                              : CachedNetworkImage(
                                                imageUrl: entry.imageUrl,
                                                cacheManager:
                                                    AppImageCache.manager,
                                                memCacheWidth: 156,
                                                fit: BoxFit.cover,
                                              ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.subject,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.titleSmall,
                                        ),
                                        if (entry.detail.isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          BangumiRichText(
                                            entry.detail,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                            selectable: false,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (entry.subjectId > 0) ...[
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 16,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ] else if (entry.subject.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        BangumiRichText(entry.subject, selectable: false),
                      ],
                      if (_reactions.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        ReactionSummary(reactions: _reactions),
                      ],
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          const Spacer(),
                          if (entry.replies > 0) ...[
                            const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 15,
                            ),
                            const SizedBox(width: 4),
                            Text('${entry.replies}'),
                            const SizedBox(width: 6),
                          ],
                          IconButton(
                            tooltip: _selectedValue == null ? '贴贴' : '更换表情',
                            visualDensity: VisualDensity.compact,
                            onPressed: _busy ? null : _react,
                            icon:
                                _selectedValue == null
                                    ? const Icon(
                                      Icons.add_reaction_outlined,
                                      size: 19,
                                    )
                                    : BangumiReactionImage(
                                      value: _selectedValue!,
                                      size: 19,
                                    ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _dateLabel(DateTime? date) {
  if (date == null) return '时间未知';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return '今天';
  if (difference == 1) return '昨天';
  return '${date.month}月${date.day}日';
}
