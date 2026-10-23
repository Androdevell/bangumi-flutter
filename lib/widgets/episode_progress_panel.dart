import 'package:flutter/material.dart';
import '../core/localization/app_localizations.dart';
import '../core/subject_detail_models.dart';
import '../core/episode_types.dart';
import '../data/bangumi_repository.dart';
import '../features/subject/episode_progress_controller.dart';
import '../features/episode/episode_comments_page.dart';

enum _EpisodeAction {
  comments,
  collect,
  recheck,
  done,
  wish,
  dropped,
  undo,
  until;

  int get status => switch (this) {
    wish => EpisodeStatus.wish,
    dropped => EpisodeStatus.dropped,
    undo => EpisodeStatus.none,
    _ => EpisodeStatus.done,
  };
}

String episodeStatusKey(int value) => switch (value) {
  EpisodeStatus.wish => 'episodeWish',
  EpisodeStatus.done => 'episodeDone',
  EpisodeStatus.dropped => 'episodeDropped',
  _ => 'episodeNone',
};

class EpisodeProgressPanel extends StatelessWidget {
  const EpisodeProgressPanel({
    super.key,
    required this.controller,
    required this.repository,
    this.expanded = false,
    this.onCollect,
    this.onViewAll,
  });
  final EpisodeProgressController controller;
  final BangumiRepository repository;
  final bool expanded;
  final VoidCallback? onCollect;
  final VoidCallback? onViewAll;
  Future<void> _open(BuildContext context, SubjectEpisode episode) async {
    final strings = AppLocalizations.of(context);
    final session = controller.repository.scope;
    final action = await showModalBottomSheet<_EpisodeAction>(
      context: context,
      showDragHandle: true,
      builder:
          (_) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text('${episode.sort} · ${episode.title}'),
                    subtitle: Text(
                      '${episode.airdate.isEmpty ? strings.t('unknownAirdate') : episode.airdate} · ${strings.t(episodeStatusKey(episode.collectionStatus))}',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: Text(strings.t('viewComments')),
                    onTap:
                        () => Navigator.pop(context, _EpisodeAction.comments),
                  ),
                  if (repository.isLoggedIn) ...[
                    if (controller.state.collected != true)
                      ListTile(
                        title: Text(
                          strings.t(
                            controller.state.collected == null
                                ? 'collectionUnknown'
                                : 'collectBeforeProgress',
                          ),
                        ),
                        trailing:
                            controller.state.collected == null
                                ? const Icon(Icons.refresh)
                                : onCollect == null
                                ? null
                                : const Icon(Icons.bookmark_add_outlined),
                        onTap:
                            controller.state.collected == null
                                ? () => Navigator.pop(
                                  context,
                                  _EpisodeAction.recheck,
                                )
                                : onCollect == null
                                ? null
                                : () => Navigator.pop(
                                  context,
                                  _EpisodeAction.collect,
                                ),
                      ),
                    for (final option in [
                      _EpisodeAction.done,
                      _EpisodeAction.wish,
                      _EpisodeAction.dropped,
                      _EpisodeAction.undo,
                    ])
                      ListTile(
                        title: Text(
                          '${strings.t('markEpisode')} · ${strings.t(option == _EpisodeAction.undo ? 'episodeUndo' : episodeStatusKey(option.status))}',
                        ),
                        enabled: controller.state.collected == true,
                        onTap:
                            controller.state.collected == true
                                ? () => Navigator.pop(context, option)
                                : null,
                      ),
                    ListTile(
                      leading: const Icon(Icons.done_all),
                      title: Text(strings.t('markUntil')),
                      enabled: controller.state.collected == true,
                      onTap:
                          controller.state.collected == true
                              ? () =>
                                  Navigator.pop(context, _EpisodeAction.until)
                              : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
    );
    if (action == null || !context.mounted) return;
    if (action == _EpisodeAction.recheck) {
      await controller.refresh();
      return;
    }
    if (action == _EpisodeAction.collect) {
      onCollect?.call();
      return;
    }
    if (action == _EpisodeAction.comments) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) =>
                  EpisodeCommentsPage(episode: episode, repository: repository),
        ),
      );
      return;
    }
    if (action == _EpisodeAction.until) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              content: Text(strings.t('markUntilConfirm')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(strings.t('cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(strings.t('confirm')),
                ),
              ],
            ),
      );
      if (confirmed != true) return;
    }
    if (!context.mounted) return;
    if (session != controller.repository.scope) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.t('commentSessionChanged'))),
      );
      return;
    }
    await controller.save(
      episode,
      action.status,
      batch: action == _EpisodeAction.until,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final state = controller.state;
      final page = state.page;
      final items = page?.items ?? const <SubjectEpisode>[];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      bool aired(SubjectEpisode e) {
        final date = DateTime.tryParse(e.airdate);
        return date != null && !date.isAfter(today);
      }

      final known =
          items.where((e) => DateTime.tryParse(e.airdate) != null).length;
      final children = <Widget>[
        Row(
          children: [
            const Icon(Icons.view_module_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.t('episodeProgress'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: strings.t('refresh'),
              onPressed:
                  state.loading || state.busyId != null
                      ? null
                      : controller.refresh,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        if (state.loading) const LinearProgressIndicator(minHeight: 2),
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${page?.hasMore == true || (page?.offset ?? 0) > 0 ? '${strings.t('currentPage')} · ' : ''}${strings.t('aired')} ${items.where(aired).length}/$known${repository.isLoggedIn ? ' · ${strings.t('watchedEpisodes')} ${items.where((e) => e.collectionStatus == EpisodeStatus.done).length}' : ''}${page?.hasMore == true || (page?.offset ?? 0) > 0 ? ' · ${strings.t('allEpisodes')}: ${page?.total ?? '—'}' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (state.error != null)
          TextButton.icon(
            onPressed: state.busyId == null ? controller.refresh : null,
            icon: const Icon(Icons.refresh),
            label: Text(
              '${strings.t(state.saved ? 'progressRefreshFailed' : 'retry')} · ${state.error}',
            ),
          ),
        if (items.isEmpty && !state.loading && state.error == null)
          Text(strings.t('episodeNone')),
        if (!expanded)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final episode in items.take(24))
                Builder(
                  builder: (context) {
                    final scheme = Theme.of(context).colorScheme;
                    final done = episode.collectionStatus == EpisodeStatus.done;
                    final label =
                        '${episode.type == EpisodeKind.main ? '' : 'SP '}${episode.sort.toString().replaceAll(RegExp(r'\.0$'), '')}';
                    return Tooltip(
                      message:
                          '${episode.title}\n${episode.airdate.isEmpty ? strings.t('unknownAirdate') : episode.airdate}\n${strings.t(episodeStatusKey(episode.collectionStatus))}',
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor:
                                done
                                    ? scheme.primaryContainer
                                    : episode.collectionStatus ==
                                        EpisodeStatus.dropped
                                    ? scheme.errorContainer
                                    : scheme.surfaceContainerHigh,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color:
                                    aired(episode)
                                        ? scheme.primary
                                        : scheme.outlineVariant,
                              ),
                            ),
                          ),
                          onPressed:
                              state.busyId != null
                                  ? null
                                  : () => _open(context, episode),
                          child:
                              state.busyId == episode.id
                                  ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        label,
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.labelMedium,
                                      ),
                                      if (episode.collectionStatus !=
                                          EpisodeStatus.none)
                                        Icon(
                                          done
                                              ? Icons.check
                                              : episode.collectionStatus ==
                                                  EpisodeStatus.wish
                                              ? Icons.bookmark_border
                                              : Icons.close,
                                          size: 12,
                                        ),
                                    ],
                                  ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        if (!expanded && onViewAll != null)
          TextButton.icon(
            onPressed: onViewAll,
            icon: const Icon(Icons.list),
            label: Text(strings.t('allEpisodes')),
          ),
        if (page != null && (page.offset > 0 || page.hasMore))
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed:
                    page.offset > 0 && !state.loading && state.busyId == null
                        ? () => controller.refresh(
                          offset: (page.offset - page.limit).clamp(
                            0,
                            page.offset,
                          ),
                        )
                        : null,
                child: Text(strings.t('previous')),
              ),
              TextButton(
                onPressed:
                    page.hasMore && !state.loading && state.busyId == null
                        ? () => controller.refresh(offset: page.nextOffset)
                        : null,
                child: Text(strings.t('next')),
              ),
            ],
          ),
      ];
      if (expanded) {
        return ListView.builder(
          key: const PageStorageKey('episode-progress-list'),
          padding: const EdgeInsets.all(16),
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              );
            }
            final episode = items[index - 1];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text(
                episode.sort.toString().replaceAll(RegExp(r'\.0$'), ''),
              ),
              title: Text(episode.title),
              subtitle: Text(
                '${episode.airdate.isEmpty ? strings.t('unknownAirdate') : episode.airdate} · ${episode.duration}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, episode),
            );
          },
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    },
  );
}
