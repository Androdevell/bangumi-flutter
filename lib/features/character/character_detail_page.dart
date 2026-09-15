import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/community_models.dart';
import '../../core/network/app_image_cache.dart';
import '../../core/network/api_client.dart';
import '../../data/bangumi_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/subject_card.dart';
import '../community/community_widgets.dart';
import '../subject/subject_detail_page.dart';
import '../user/user_profile_page.dart';

class CharacterDetailPage extends StatefulWidget {
  const CharacterDetailPage({
    super.key,
    required this.characterId,
    required this.repository,
  });
  final int characterId;
  final BangumiRepository repository;

  @override
  State<CharacterDetailPage> createState() => _CharacterDetailPageState();
}

class _CharacterDetailPageState extends State<CharacterDetailPage> {
  late Future<CharacterDetailData> _details = _load();
  bool? _collected;
  bool _busy = false;

  Future<CharacterDetailData> _load() =>
      widget.repository.fetchCharacterDetails(widget.characterId);

  Future<void> _toggle(CharacterEntry character) async {
    if (!widget.repository.isLoggedIn) {
      _message('请先登录后再收藏角色');
      return;
    }
    if (_busy) return;
    final current = _collected ?? character.collected;
    setState(() => _busy = true);
    try {
      await widget.repository.toggleCharacterCollection(character.id, current);
      if (mounted) setState(() => _collected = !current);
    } on Object catch (error) {
      _message('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
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
  Widget build(BuildContext context) => FutureBuilder<CharacterDetailData>(
    future: _details,
    builder: (context, snapshot) {
      final data = snapshot.data;
      return DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
            title: Text(data?.character.name ?? '角色详情'),
            actions: [
              if (data != null)
                IconButton(
                  tooltip:
                      (_collected ?? data.character.collected)
                          ? '取消收藏'
                          : '收藏角色',
                  onPressed: _busy ? null : () => _toggle(data.character),
                  icon: Icon(
                    (_collected ?? data.character.collected)
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                  ),
                ),
            ],
          ),
          body:
              snapshot.hasError
                  ? NetworkErrorView(
                    error: snapshot.error!,
                    onRetry: () => setState(() => _details = _load()),
                  )
                  : data == null
                  ? const LoadingView(label: '正在加载角色资料…')
                  : SafeArea(
                    child: ContentFrame(
                      maxWidth: 1050,
                      child: Column(
                        children: [
                          _CharacterHeader(character: data.character),
                          const TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: [
                              Tab(text: '概览'),
                              Tab(text: '出演'),
                              Tab(text: '收藏'),
                              Tab(text: '吐槽'),
                              Tab(text: '目录'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _Overview(character: data.character),
                                _Works(
                                  items: data.works,
                                  repository: widget.repository,
                                ),
                                _Collectors(
                                  items: data.collectors,
                                  onUserTap: _openUser,
                                ),
                                CommunityReplyList(
                                  items: data.comments,
                                  currentUsername:
                                      widget.repository.currentUsername,
                                  onUserTap: _openUser,
                                  onLike:
                                      (_, __) async =>
                                          throw const ApiException(
                                            '角色吐槽暂不支持点赞',
                                          ),
                                ),
                                _Indexes(items: data.indexes),
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

class _CharacterHeader extends StatelessWidget {
  const _CharacterHeader({required this.character});
  final CharacterEntry character;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child:
              character.imageUrl.isEmpty
                  ? const SizedBox(
                    width: 92,
                    height: 124,
                    child: ColoredBox(
                      color: Colors.black12,
                      child: Icon(Icons.theater_comedy_outlined),
                    ),
                  )
                  : CachedNetworkImage(
                    imageUrl: character.imageUrl,
                    cacheManager: AppImageCache.manager,
                    width: 92,
                    height: 124,
                    memCacheWidth: 300,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                character.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (character.originalName != character.name)
                Text(character.originalName),
              const SizedBox(height: 8),
              Text(character.info),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.favorite_outline_rounded, size: 18),
                  const SizedBox(width: 5),
                  Text('${character.collects} 人收藏'),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Overview extends StatelessWidget {
  const _Overview({required this.character});
  final CharacterEntry character;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      if (character.summary.isNotEmpty) ...[
        Text('简介', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        SelectableText(character.summary),
        const SizedBox(height: 24),
      ],
      Text('资料', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      for (final line in character.infobox)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SelectableText(line),
        ),
    ],
  );
}

class _Works extends StatelessWidget {
  const _Works({required this.items, required this.repository});
  final List<CharacterWork> items;
  final BangumiRepository repository;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyView(message: '暂无出演作品');
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final item = items[index];
        return ListTile(
          leading: SizedBox(
            width: 48,
            height: 66,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: PosterArt(subject: item.subject, cacheWidth: 180),
            ),
          ),
          title: Text(item.subject.title),
          subtitle: Text(
            item.actors.isEmpty
                ? item.subject.typeLabel
                : item.actors.join('、'),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap:
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder:
                      (_) => SubjectDetailPage(
                        subject: item.subject,
                        heroTag: 'character-work-${item.subject.id}',
                        repository: repository,
                      ),
                ),
              ),
        );
      },
    );
  }
}

class _Collectors extends StatelessWidget {
  const _Collectors({required this.items, required this.onUserTap});
  final List<CommunityUser> items;
  final ValueChanged<String> onUserTap;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyView(message: '暂无收藏用户');
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final user = items[index];
        return ListTile(
          leading: CommunityAvatar(user: user),
          title: Text(user.nickname),
          subtitle: Text('@${user.username}'),
          onTap: () => onUserTap(user.username),
        );
      },
    );
  }
}

class _Indexes extends StatelessWidget {
  const _Indexes({required this.items});
  final List<UserContentItem> items;
  @override
  Widget build(BuildContext context) =>
      items.isEmpty
          ? const EmptyView(message: '暂无关联目录')
          : ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder:
                (_, index) => ListTile(
                  leading: const Icon(Icons.list_alt_outlined),
                  title: Text(items[index].title),
                  subtitle: Text(items[index].subtitle),
                ),
          );
}
