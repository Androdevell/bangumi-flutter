import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/app_strings.dart';
import '../../core/models.dart';
import '../../core/network/app_image_cache.dart';
import '../../data/bangumi_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/subject_card.dart';
import '../search/subject_search_delegate.dart';
import '../subject/subject_detail_page.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key, required this.repository});

  final BangumiRepository repository;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  bool _grid = true;
  int _selectedDay = DateTime.now().weekday - 1;
  late Future<Map<String, List<Subject>>> _calendar =
      widget.repository.fetchCalendar();
  final Set<String> _warmedPosters = {};

  static const _apiDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  Future<void> _refresh() async {
    final future = widget.repository.fetchCalendar();
    setState(() => _calendar = future);
    await future;
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
    final now = DateTime.now();
    return SafeArea(
      child: ContentFrame(
        child: FutureBuilder<Map<String, List<Subject>>>(
          future: _calendar,
          builder: (context, snapshot) {
            final calendar = snapshot.data;
            final subjects =
                calendar == null
                    ? const <Subject>[]
                    : _subjectsForDay(calendar);
            _warmPosters(subjects);
            return RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                key: const PageStorageKey('discover-scroll'),
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
                    sliver: SliverToBoxAdapter(
                      child: PageHeader(
                        title: AppStrings.discover,
                        subtitle:
                            '${now.year} 年 ${now.month} 月 ${now.day} 日 · ${_dayLabels[now.weekday - 1]}',
                        actions: [
                          IconButton.filledTonal(
                            tooltip: '刷新',
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
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
                    padding: const EdgeInsets.fromLTRB(24, 18, 16, 4),
                    sliver: SliverToBoxAdapter(
                      child: SectionHeader(
                        title: AppStrings.today,
                        actionLabel: _grid ? '列表' : '网格',
                        onAction: () => setState(() => _grid = !_grid),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                    sliver: SliverToBoxAdapter(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (
                              var index = 0;
                              index < _dayLabels.length;
                              index++
                            )
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    index == now.weekday - 1
                                        ? '今天'
                                        : _dayLabels[index],
                                  ),
                                  selected: _selectedDay == index,
                                  onSelected:
                                      (_) =>
                                          setState(() => _selectedDay = index),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (snapshot.connectionState != ConnectionState.done &&
                      calendar == null)
                    const SliverFillRemaining(child: LoadingView())
                  else if (snapshot.hasError && calendar == null)
                    SliverFillRemaining(
                      child: NetworkErrorView(
                        error: snapshot.error!,
                        onRetry: _refresh,
                      ),
                    )
                  else if (subjects.isEmpty)
                    const SliverFillRemaining(
                      child: EmptyView(message: '这一天暂无放送条目'),
                    )
                  else if (_grid)
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
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
                      sliver: SliverList.separated(
                        itemCount: subjects.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder:
                            (context, index) => _SubjectLine(
                              subject: subjects[index],
                              repository: widget.repository,
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

  List<Subject> _subjectsForDay(Map<String, List<Subject>> calendar) {
    final english = calendar[_apiDays[_selectedDay]];
    if (english != null) return english;
    final chinese = calendar[_dayLabels[_selectedDay]];
    if (chinese != null) return chinese;
    final values = calendar.values.toList();
    return _selectedDay < values.length ? values[_selectedDay] : const [];
  }
}

class _SubjectLine extends StatelessWidget {
  const _SubjectLine({required this.subject, required this.repository});

  final Subject subject;
  final BangumiRepository repository;

  @override
  Widget build(BuildContext context) {
    return SurfaceBlock(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap:
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder:
                    (_) => SubjectDetailPage(
                      subject: subject,
                      heroTag: 'line-${subject.id}',
                      repository: repository,
                    ),
              ),
            ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                height: 82,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: PosterArt(subject: subject),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subject.subtitle.isEmpty
                          ? subject.originalTitle
                          : subject.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (subject.score > 0) ...[
                Icon(
                  Icons.star_rounded,
                  size: 17,
                  color: Colors.amber.shade700,
                ),
                const SizedBox(width: 3),
                Text(subject.score.toStringAsFixed(1)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
