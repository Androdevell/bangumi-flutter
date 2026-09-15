import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/app_strings.dart';
import '../../core/models.dart';
import '../../core/network/app_image_cache.dart';
import '../../data/bangumi_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/subject_card.dart';
import '../search/subject_search_delegate.dart';

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, required this.repository});

  final BangumiRepository repository;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  int _type = 0;
  int _sort = 0;
  late Future<List<Subject>> _subjects = _load();
  final Set<String> _warmedPosters = {};

  static const _types = [
    ('动画', 2),
    ('书籍', 1),
    ('音乐', 3),
    ('游戏', 4),
    ('三次元', 6),
  ];
  static const _sorts = [('热门', 'trends'), ('评分', 'rank'), ('日期', 'date')];

  Future<List<Subject>> _load() => widget.repository.fetchSubjects(
    type: _types[_type].$2,
    sort: _sorts[_sort].$2,
  );

  Future<void> _reload() async {
    final future = _load();
    setState(() => _subjects = future);
    await future;
  }

  void _changeFilters({int? type, int? sort}) {
    setState(() {
      if (type != null) _type = type;
      if (sort != null) _sort = sort;
      _subjects = _load();
    });
  }

  void _warmPosters(List<Subject> subjects) {
    final pending =
        subjects
            .map((item) => item.imageUrl)
            .where((url) => url.isNotEmpty && _warmedPosters.add(url))
            .toList();
    if (pending.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final url in pending) {
        precacheImage(
          CachedNetworkImageProvider(
            url,
            cacheManager: AppImageCache.manager,
            maxWidth: 520,
          ),
          context,
          onError: (_, __) {},
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ContentFrame(
        child: FutureBuilder<List<Subject>>(
          future: _subjects,
          builder: (context, snapshot) {
            final subjects = snapshot.data ?? const <Subject>[];
            _warmPosters(subjects);
            return RefreshIndicator(
              onRefresh: _reload,
              child: CustomScrollView(
                key: const PageStorageKey('browse-scroll'),
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(24, 22, 24, 18),
                    sliver: SliverToBoxAdapter(
                      child: PageHeader(
                        title: AppStrings.browse,
                        subtitle: '按类型与热度发现新条目',
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverToBoxAdapter(
                      child: TextField(
                        readOnly: true,
                        onTap:
                            () => showSearch<void>(
                              context: context,
                              delegate: SubjectSearchDelegate(
                                repository: widget.repository,
                                type: _types[_type].$2,
                              ),
                            ),
                        decoration: const InputDecoration(
                          hintText: AppStrings.searchHint,
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                    sliver: SliverToBoxAdapter(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var index = 0; index < _types.length; index++)
                            ChoiceChip(
                              label: Text(_types[index].$1),
                              selected: _type == index,
                              onSelected: (_) => _changeFilters(type: index),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 2, 16, 10),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_types[_type].$1}条目',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          PopupMenuButton<int>(
                            tooltip: '排序',
                            initialValue: _sort,
                            onSelected: (value) => _changeFilters(sort: value),
                            itemBuilder:
                                (_) => [
                                  for (
                                    var index = 0;
                                    index < _sorts.length;
                                    index++
                                  )
                                    PopupMenuItem(
                                      value: index,
                                      child: Text('${_sorts[index].$1}排序'),
                                    ),
                                ],
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.sort_rounded),
                                  const SizedBox(width: 6),
                                  Text(_sorts[_sort].$1),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (snapshot.connectionState != ConnectionState.done &&
                      subjects.isEmpty)
                    const SliverFillRemaining(child: LoadingView())
                  else if (snapshot.hasError && subjects.isEmpty)
                    SliverFillRemaining(
                      child: NetworkErrorView(
                        error: snapshot.error!,
                        onRetry: _reload,
                      ),
                    )
                  else if (subjects.isEmpty)
                    const SliverFillRemaining(child: EmptyView())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: 0.67,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => SubjectCard(
                            subject: subjects[index],
                            index: subjects[index].id,
                            repository: widget.repository,
                          ),
                          childCount: subjects.length,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
