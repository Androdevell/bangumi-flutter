import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import 'discover_controller.dart';
import '../../core/models.dart';
import '../../data/bangumi_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/subject_card.dart';
import '../search/subject_search_delegate.dart';
import '../subject/subject_navigation.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key, required this.repository});

  final BangumiRepository repository;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  bool _grid = true;
  int _selectedDay = DateTime.now().weekday - 1;
  late final DiscoverController _controller = DiscoverController(
    widget.repository,
  );
  @override
  void initState() {
    super.initState();
    _controller.dispatch(LoadDiscover());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _apiDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  Future<void> _refresh() async {
    await _controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final strings = AppLocalizations.of(context);
    final days = switch (strings.locale.languageCode) {
      'en' => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      'ja' => const ['月曜', '火曜', '水曜', '木曜', '金曜', '土曜', '日曜'],
      _ => _dayLabels,
    };
    return SafeArea(
      child: ContentFrame(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final state = _controller.state;
            final calendar = state.calendar;
            final subjects =
                calendar == null
                    ? const <Subject>[]
                    : _subjectsForDay(calendar);
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
                        title: strings.t('discover'),
                        subtitle: MaterialLocalizations.of(
                          context,
                        ).formatFullDate(now),
                        actions: [
                          IconButton.filledTonal(
                            tooltip: strings.t('refresh'),
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
                        decoration: InputDecoration(
                          hintText: strings.t('searchHint'),
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 16, 4),
                    sliver: SliverToBoxAdapter(
                      child: SectionHeader(
                        title: strings.t('todayBroadcast'),
                        actionLabel: strings.t(_grid ? 'listView' : 'gridView'),
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
                                        ? strings.t('today')
                                        : days[index],
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
                  SliverToBoxAdapter(
                    child: Semantics(
                      label: state.loading ? strings.t('loading') : null,
                      liveRegion: true,
                      child: SizedBox(
                        height: 2,
                        child:
                            state.loading && calendar != null
                                ? const LinearProgressIndicator(minHeight: 2)
                                : null,
                      ),
                    ),
                  ),
                  if (state.error != null && calendar != null)
                    SliverToBoxAdapter(
                      child: TextButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: Text('${strings.t('retry')} · ${state.error}'),
                      ),
                    ),
                  if (state.loading && calendar == null)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: .60,
                            ),
                        itemCount: 8,
                        itemBuilder: (_, __) => const _CalendarSkeleton(),
                      ),
                    )
                  else if (state.error != null && calendar == null)
                    SliverFillRemaining(
                      child: NetworkErrorView(
                        error: state.error!,
                        onRetry: _refresh,
                      ),
                    )
                  else if (subjects.isEmpty)
                    SliverFillRemaining(
                      child: EmptyView(message: strings.t('calendarEmpty')),
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
                              childAspectRatio: 0.60,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => SubjectCard(
                            key: ValueKey(
                              'calendar:$_selectedDay:${subjects[index].id}',
                            ),
                            subject: subjects[index],
                            heroTag:
                                'discover-$_selectedDay-${subjects[index].id}',
                            onTap:
                                () => openSubjectDetails(
                                  context,
                                  subject: subjects[index],
                                  repository: widget.repository,
                                  heroTag:
                                      'discover-$_selectedDay-${subjects[index].id}',
                                ),
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

class _CalendarSkeleton extends StatelessWidget {
  const _CalendarSkeleton();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 12,
                  width: 60,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
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
            () => openSubjectDetails(
              context,
              subject: subject,
              heroTag: 'line-${subject.id}',
              repository: repository,
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
                  child: SubjectPosterHero(
                    subject: subject,
                    tag: 'line-${subject.id}',
                  ),
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
