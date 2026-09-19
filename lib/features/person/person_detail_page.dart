import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/community_models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/app_image_cache.dart';
import '../../data/bangumi_repository.dart';
import '../../widgets/common.dart';
import '../community/community_widgets.dart';
import '../user/user_profile_page.dart';

class PersonDetailPage extends StatefulWidget {
  const PersonDetailPage({
    super.key,
    required this.personId,
    required this.repository,
  });

  final int personId;
  final BangumiRepository repository;

  @override
  State<PersonDetailPage> createState() => _PersonDetailPageState();
}

class _PersonDetailPageState extends State<PersonDetailPage> {
  late Future<PersonDetailData> _details = _load();

  Future<PersonDetailData> _load() =>
      widget.repository.fetchPersonDetails(widget.personId);

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

  @override
  Widget build(BuildContext context) => FutureBuilder<PersonDetailData>(
    future: _details,
    builder: (context, snapshot) {
      final data = snapshot.data;
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(title: Text(data?.person.name ?? '制作人员详情')),
          body:
              snapshot.hasError
                  ? NetworkErrorView(
                    error: snapshot.error!,
                    onRetry: () => setState(() => _details = _load()),
                  )
                  : data == null
                  ? const LoadingView(label: '正在加载制作人员资料…')
                  : SafeArea(
                    child: ContentFrame(
                      maxWidth: 960,
                      child: Column(
                        children: [
                          _PersonHeader(person: data.person),
                          const TabBar(
                            tabs: [Tab(text: '详细资料'), Tab(text: '吐槽')],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _PersonOverview(person: data.person),
                                CommunityReplyList(
                                  items: data.comments,
                                  currentUsername:
                                      widget.repository.currentUsername,
                                  onUserTap: _openUser,
                                  onLike:
                                      (_, __) async =>
                                          throw const ApiException(
                                            '制作人员吐槽暂不支持点赞',
                                          ),
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
    },
  );
}

class _PersonHeader extends StatelessWidget {
  const _PersonHeader({required this.person});

  final PersonEntry person;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child:
              person.imageUrl.isEmpty
                  ? const SizedBox(
                    width: 92,
                    height: 124,
                    child: ColoredBox(
                      color: Colors.black12,
                      child: Icon(Icons.badge_outlined),
                    ),
                  )
                  : CachedNetworkImage(
                    imageUrl: person.imageUrl,
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
                person.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (person.originalName.isNotEmpty &&
                  person.originalName != person.name)
                Text(person.originalName),
              if (person.info.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(person.info),
              ],
              if (person.careers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(person.careers.join(' · ')),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.favorite_outline_rounded, size: 18),
                  const SizedBox(width: 5),
                  Text('${person.collects} 人收藏'),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PersonOverview extends StatelessWidget {
  const _PersonOverview({required this.person});

  final PersonEntry person;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      if (person.summary.isNotEmpty) ...[
        Text('简介', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        SelectableText(person.summary),
        const SizedBox(height: 24),
      ],
      Text('资料', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (person.infobox.isEmpty)
        const Text('暂无详细资料')
      else
        for (final line in person.infobox)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: SelectableText(line),
          ),
    ],
  );
}
