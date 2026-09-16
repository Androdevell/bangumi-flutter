import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/community_models.dart';
import '../../core/network/app_image_cache.dart';
import '../../data/bangumi_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/bangumi_rich_text.dart';
import '../character/character_detail_page.dart';
import '../community/community_widgets.dart';
import '../subject/subject_detail_page.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    super.key,
    required this.username,
    required this.repository,
    this.initialIndex = 0,
  });

  final String username;
  final BangumiRepository repository;
  final int initialIndex;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late Future<UserProfileData> _profile = _load();
  bool? _isFriend;
  bool _friendBusy = false;

  Future<UserProfileData> _load() =>
      widget.repository.fetchUserProfile(widget.username);

  Future<void> _toggleFriend(CommunityUser user) async {
    if (!widget.repository.isLoggedIn) {
      _message('请先登录后再添加好友');
      return;
    }
    if (_friendBusy) return;
    final current = _isFriend ?? user.isFriend;
    setState(() => _friendBusy = true);
    try {
      await widget.repository.toggleFriend(user.username, current);
      if (mounted) setState(() => _isFriend = !current);
    } on Object catch (error) {
      _message('$error');
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _openSubject(UserContentItem item) async {
    try {
      final subject = await widget.repository.fetchSubject(item.id);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => SubjectDetailPage(
                subject: subject,
                heroTag: 'user-${widget.username}-subject-${item.id}',
                repository: widget.repository,
              ),
        ),
      );
    } on Object catch (error) {
      _message('$error');
    }
  }

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
    return FutureBuilder<UserProfileData>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text('@${widget.username}')),
            body: NetworkErrorView(
              error: snapshot.error!,
              onRetry: () => setState(() => _profile = _load()),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text('@${widget.username}')),
            body: const LoadingView(label: '正在加载用户资料…'),
          );
        }
        final data = snapshot.data!;
        final user = data.user;
        final isSelf = widget.repository.currentUsername == user.username;
        final tabs = const ['时光机', '收藏', '人物', '日志', '目录', '好友', '时间线', '统计'];
        return DefaultTabController(
          length: tabs.length,
          initialIndex: widget.initialIndex.clamp(0, tabs.length - 1),
          child: Scaffold(
            appBar: AppBar(
              title: Text(user.nickname),
              actions: [
                if (!isSelf)
                  IconButton(
                    tooltip: (_isFriend ?? user.isFriend) ? '删除好友' : '添加好友',
                    onPressed: _friendBusy ? null : () => _toggleFriend(user),
                    icon: Icon(
                      (_isFriend ?? user.isFriend)
                          ? Icons.person_remove_outlined
                          : Icons.person_add_outlined,
                    ),
                  ),
              ],
            ),
            body: SafeArea(
              child: ContentFrame(
                maxWidth: 1100,
                child: Column(
                  children: [
                    _UserHeader(user: user),
                    Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [for (final tab in tabs) Tab(text: tab)],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _TimeMachine(user: user, data: data),
                          _ContentList(
                            items: data.collections,
                            empty: '暂无公开收藏',
                            onTap: _openSubject,
                            collection: true,
                          ),
                          _MonoList(data: data, repository: widget.repository),
                          _ContentList(items: data.blogs, empty: '暂无日志'),
                          _ContentList(items: data.indexes, empty: '暂无目录'),
                          _FriendList(items: data.friends, onTap: _openUser),
                          _TimelineList(items: data.timeline),
                          _StatsView(user: user),
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

class _UserHeader extends StatelessWidget {
  const _UserHeader({required this.user});
  final CommunityUser user;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
    child: Row(
      children: [
        CommunityAvatar(user: user, radius: 38),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.nickname,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('@${user.username}'),
              if (user.sign.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    user.sign,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TimeMachine extends StatelessWidget {
  const _TimeMachine({required this.user, required this.data});
  final CommunityUser user;
  final UserProfileData data;
  @override
  Widget build(BuildContext context) {
    final stats = user.stats;
    return LayoutBuilder(
      builder:
          (context, constraints) => ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  _TimeMachineStat(
                    label: '收藏',
                    value: stats.subjects,
                    icon: Icons.bookmarks_outlined,
                  ),
                  _TimeMachineStat(
                    label: '看过',
                    value: stats.watched,
                    icon: Icons.done_all_rounded,
                  ),
                  _TimeMachineStat(
                    label: '日志',
                    value: stats.blogs,
                    icon: Icons.article_outlined,
                  ),
                  _TimeMachineStat(
                    label: '好友',
                    value: stats.friends,
                    icon: Icons.people_outline_rounded,
                  ),
                ],
              ),
              if (user.joinedAt.millisecondsSinceEpoch > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '${user.joinedAt.year}-${user.joinedAt.month.toString().padLeft(2, '0')}-${user.joinedAt.day.toString().padLeft(2, '0')} 加入 Bangumi',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (user.bio.isNotEmpty) ...[
                const SizedBox(height: 18),
                SurfaceBlock(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.format_quote_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '个人简介',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SelectableText(user.bio),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (constraints.maxWidth >= 840)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _CollectionOverview(data: data)),
                    const SizedBox(width: 24),
                    Expanded(flex: 2, child: _TimelineOverview(data: data)),
                  ],
                )
              else ...[
                _CollectionOverview(data: data),
                const SizedBox(height: 26),
                _TimelineOverview(data: data),
              ],
            ],
          ),
    );
  }
}

class _CollectionOverview extends StatelessWidget {
  const _CollectionOverview({required this.data});
  final UserProfileData data;

  @override
  Widget build(BuildContext context) {
    const types = <int, String>{2: '动画', 1: '书籍', 4: '游戏', 3: '音乐', 6: '三次元'};
    final groups = <(String, List<UserContentItem>)>[];
    for (final entry in types.entries) {
      final items =
          data.collections
              .where((item) => item.subjectType == entry.key)
              .toList();
      if (items.isNotEmpty) groups.add((entry.value, items));
    }
    if (groups.isEmpty) return const EmptyView(message: '暂无公开收藏');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('我的收藏', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final group in groups) ...[
          Row(
            children: [
              Text(group.$1, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              Text(
                '最近 ${group.$2.length} 项',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 155,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: group.$2.take(8).length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) {
                final item = group.$2[index];
                return SizedBox(
                  width: 86,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedNetworkImage(
                          imageUrl: item.imageUrl,
                          cacheManager: AppImageCache.manager,
                          width: 86,
                          height: 112,
                          memCacheWidth: 258,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _TimelineOverview extends StatelessWidget {
  const _TimelineOverview({required this.data});
  final UserProfileData data;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text('我的时间胶囊', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          Text(
            '${data.timeline.length} 条',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (data.timeline.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(child: Text('暂无公开动态')),
        )
      else
        for (final item in data.timeline.take(12))
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(top: 15),
                      decoration: BoxDecoration(
                        color: item.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        width: 1,
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BangumiRichText(
                          '${item.action}  ${item.subject}',
                          selectable: false,
                        ),
                        if (item.detail.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          BangumiRichText(
                            item.detail,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                            selectable: false,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          item.relativeTime(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
    ],
  );
}

class _TimeMachineStat extends StatelessWidget {
  const _TimeMachineStat({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 125,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: Theme.of(context).textTheme.titleMedium),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    ),
  );
}

class _ContentList extends StatelessWidget {
  const _ContentList({
    required this.items,
    required this.empty,
    this.onTap,
    this.collection = false,
  });
  final List<UserContentItem> items;
  final String empty;
  final ValueChanged<UserContentItem>? onTap;
  final bool collection;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return EmptyView(message: empty);
    if (collection) {
      return GridView.builder(
        padding: const EdgeInsets.all(14),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 390,
          mainAxisExtent: 126,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: items.length,
        itemBuilder: (_, index) {
          final item = items[index];
          return SurfaceBlock(
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap == null ? null : () => onTap!(item),
              child: Row(
                children: [
                  if (item.imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(7),
                      ),
                      child: CachedNetworkImage(
                        imageUrl: item.imageUrl,
                        cacheManager: AppImageCache.manager,
                        width: 84,
                        height: 126,
                        memCacheWidth: 252,
                        fit: BoxFit.cover,
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.subtitle.isEmpty ? '已收藏' : item.subtitle,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final item = items[index];
        return ListTile(
          leading:
              item.imageUrl.isEmpty
                  ? const Icon(Icons.article_outlined)
                  : ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: CachedNetworkImage(
                      imageUrl: item.imageUrl,
                      cacheManager: AppImageCache.manager,
                      width: 48,
                      height: 64,
                      memCacheWidth: 160,
                      fit: BoxFit.cover,
                    ),
                  ),
          title: Text(item.title),
          subtitle:
              item.subtitle.isEmpty
                  ? null
                  : Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
          trailing:
              onTap == null ? null : const Icon(Icons.chevron_right_rounded),
          onTap: onTap == null ? null : () => onTap!(item),
        );
      },
    );
  }
}

class _MonoList extends StatelessWidget {
  const _MonoList({required this.data, required this.repository});
  final UserProfileData data;
  final BangumiRepository repository;
  @override
  Widget build(BuildContext context) {
    final items = [
      ...data.characters.map((e) => (e, true)),
      ...data.persons.map((e) => (e, false)),
    ];
    if (items.isEmpty) return const EmptyView(message: '暂无人物收藏');
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final entry = items[index];
        final item = entry.$1;
        return ListTile(
          leading: SizedBox(
            width: 42,
            height: 42,
            child: ClipOval(
              child:
                  item.imageUrl.isEmpty
                      ? ColoredBox(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        child: const Icon(Icons.person_outline_rounded),
                      )
                      : CachedNetworkImage(
                        imageUrl: item.imageUrl,
                        cacheManager: AppImageCache.manager,
                        memCacheWidth: 160,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
            ),
          ),
          title: Text(item.title),
          subtitle: Text(entry.$2 ? '角色' : '人物'),
          trailing: entry.$2 ? const Icon(Icons.chevron_right_rounded) : null,
          onTap:
              entry.$2
                  ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder:
                          (_) => CharacterDetailPage(
                            characterId: item.id,
                            repository: repository,
                          ),
                    ),
                  )
                  : null,
        );
      },
    );
  }
}

class _FriendList extends StatelessWidget {
  const _FriendList({required this.items, required this.onTap});
  final List<CommunityUser> items;
  final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyView(message: '暂无公开好友');
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final user = items[index];
        return ListTile(
          leading: CommunityAvatar(
            user: user,
            onTap: () => onTap(user.username),
          ),
          title: Text(user.nickname),
          subtitle: Text(
            user.sign.isEmpty ? '@${user.username}' : user.sign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => onTap(user.username),
        );
      },
    );
  }
}

class _TimelineList extends StatelessWidget {
  const _TimelineList({required this.items});
  final List<dynamic> items;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyView(message: '暂无公开时间线');
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final item = items[index];
        return ListTile(
          leading:
              item.imageUrl.isEmpty
                  ? const Icon(Icons.timeline_rounded)
                  : ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: CachedNetworkImage(
                      imageUrl: item.imageUrl,
                      cacheManager: AppImageCache.manager,
                      width: 42,
                      height: 56,
                      memCacheWidth: 126,
                      fit: BoxFit.cover,
                    ),
                  ),
          title: BangumiRichText(item.subject, selectable: false),
          subtitle: BangumiRichText(
            '${item.action} · ${item.relativeTime()}${item.detail.isEmpty ? '' : '\n${item.detail}'}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            selectable: false,
          ),
        );
      },
    );
  }
}

class _StatsView extends StatelessWidget {
  const _StatsView({required this.user});
  final CommunityUser user;
  @override
  Widget build(BuildContext context) {
    final stats = user.stats;
    final entries = [
      ('全部收藏', stats.subjects, Icons.bookmarks_outlined),
      ('看过', stats.watched, Icons.done_all_rounded),
      ('角色', stats.characters, Icons.theater_comedy_outlined),
      ('人物', stats.persons, Icons.person_search_outlined),
      ('日志', stats.blogs, Icons.article_outlined),
      ('目录', stats.indexes, Icons.list_alt_outlined),
      ('好友', stats.friends, Icons.people_outline_rounded),
      ('小组', stats.groups, Icons.groups_outlined),
    ];
    return GridView.builder(
      padding: const EdgeInsets.all(18),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 108,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: entries.length,
      itemBuilder:
          (_, index) => SurfaceBlock(
            child: Row(
              children: [
                Icon(entries[index].$3),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entries[index].$2}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(entries[index].$1),
                  ],
                ),
              ],
            ),
          ),
    );
  }
}
