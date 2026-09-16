import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/models.dart';
import '../../core/network/app_image_cache.dart';
import '../../data/bangumi_repository.dart';
import '../../widgets/common.dart';
import '../character/character_detail_page.dart';
import '../episode/episode_comments_page.dart';
import '../subject/subject_detail_page.dart';
import '../user/user_profile_page.dart';
import '../../core/subject_detail_models.dart';
import 'person_comments_page.dart';
import 'topic_detail_page.dart';

class RakuenPage extends StatefulWidget {
  const RakuenPage({super.key, required this.repository});
  final BangumiRepository repository;

  @override
  State<RakuenPage> createState() => _RakuenPageState();
}

class _RakuenPageState extends State<RakuenPage> {
  int _category = 0;
  late Future<List<Topic>> _topics = _load();

  static const _categories = [
    ('全部', 'all', Icons.dynamic_feed_outlined),
    ('小组', 'group', Icons.groups_outlined),
    ('我的小组', 'my_group', Icons.group_work_outlined),
    ('条目', 'subject', Icons.movie_filter_outlined),
    ('章节', 'episode', Icons.playlist_play_rounded),
    ('角色', 'character', Icons.theater_comedy_outlined),
    ('人物', 'person', Icons.person_search_outlined),
  ];

  Future<List<Topic>> _load() =>
      widget.repository.fetchTopics(type: _categories[_category].$2);

  Future<void> _reload() async {
    final future = _load();
    setState(() => _topics = future);
    await future;
  }

  void _select(int value) {
    if (value == _category) return;
    setState(() {
      _category = value;
      _topics = _load();
    });
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

  Future<void> _openTopic(Topic topic) async {
    if (topic.type == 'group' || topic.type == 'subject') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) =>
                  TopicDetailPage(topic: topic, repository: widget.repository),
        ),
      );
      return;
    }
    if (topic.type == 'episode' || topic.type == 'ep') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => EpisodeCommentsPage(
                episode: SubjectEpisode(
                  id: topic.id,
                  sort: topic.episodeSort,
                  name: topic.episodeName,
                  nameCn: topic.episodeName,
                  duration: '',
                  airdate: '',
                  commentCount: topic.replies,
                  description: '',
                ),
                repository: widget.repository,
              ),
        ),
      );
      return;
    }
    if (topic.type == 'character') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => CharacterDetailPage(
                characterId: topic.id,
                repository: widget.repository,
              ),
        ),
      );
      return;
    }
    if (topic.type == 'person') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => PersonCommentsPage(
                topic: topic,
                repository: widget.repository,
              ),
        ),
      );
      return;
    }
    if (topic.subjectId > 0) {
      try {
        final subject = await widget.repository.fetchSubject(topic.subjectId);
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder:
                (_) => SubjectDetailPage(
                  subject: subject,
                  heroTag: 'rakuen-${topic.type}-${topic.id}',
                  repository: widget.repository,
                ),
          ),
        );
        return;
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${topic.typeLabel}详情接口尚未开放')));
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ContentFrame(
      maxWidth: 980,
      child: FutureBuilder<List<Topic>>(
        future: _topics,
        builder: (context, snapshot) {
          final topics = snapshot.data ?? const <Topic>[];
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              key: const PageStorageKey('rakuen-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
              children: [
                PageHeader(
                  title: AppStrings.rakuen,
                  subtitle: '全站实时讨论与章节动态',
                  actions: [
                    IconButton.filledTonal(
                      tooltip: '刷新',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var index = 0; index < _categories.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: Icon(_categories[index].$3, size: 17),
                            label: Text(_categories[index].$1),
                            selected: _category == index,
                            onSelected:
                                _categories[index].$2 == 'my_group' &&
                                        !widget.repository.isLoggedIn
                                    ? null
                                    : (_) => _select(index),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (snapshot.connectionState != ConnectionState.done &&
                    topics.isEmpty)
                  const LoadingView()
                else if (snapshot.hasError && topics.isEmpty)
                  NetworkErrorView(error: snapshot.error!, onRetry: _reload)
                else if (topics.isEmpty)
                  const EmptyView(message: '暂无讨论')
                else
                  for (final topic in topics)
                    _TopicTile(
                      topic: topic,
                      onTap: () => _openTopic(topic),
                      onUserTap: () => _openUser(topic.creatorUsername),
                    ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    required this.topic,
    required this.onTap,
    required this.onUserTap,
  });
  final Topic topic;
  final VoidCallback onTap;
  final VoidCallback onUserTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hot = topic.replies >= 20;
    final fresh = DateTime.now().difference(topic.updatedAt).inMinutes <= 20;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: topic.creatorUsername.isEmpty ? onTap : onUserTap,
                borderRadius: BorderRadius.circular(7),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(
                    width: 48,
                    height: 58,
                    child:
                        topic.avatarUrl.isNotEmpty || topic.imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                              imageUrl:
                                  topic.avatarUrl.isNotEmpty
                                      ? topic.avatarUrl
                                      : topic.imageUrl,
                              cacheManager: AppImageCache.manager,
                              memCacheWidth: 160,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                            )
                            : ColoredBox(
                              color: scheme.secondaryContainer,
                              child: Icon(
                                Icons.forum_outlined,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          topic.group,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        _TopicBadge(
                          label: topic.typeLabel,
                          color: scheme.tertiary,
                        ),
                        if (hot) _TopicBadge(label: '火热', color: scheme.error),
                        if (fresh)
                          _TopicBadge(label: '新', color: scheme.primary),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      topic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (topic.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        topic.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        if (topic.creatorName.isNotEmpty)
                          Flexible(
                            child: Text(
                              '@${topic.creatorName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        const Spacer(),
                        Text(
                          topic.relativeTime(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                        const SizedBox(width: 4),
                        Text('${topic.replies}'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicBadge extends StatelessWidget {
  const _TopicBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
    ),
  );
}
