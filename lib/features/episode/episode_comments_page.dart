import 'package:flutter/material.dart';
import '../../core/community_models.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/subject_detail_models.dart';
import '../../data/bangumi_repository.dart';
import '../../domain/use_cases/comment_submit_use_case.dart';
import '../community/comment_reading_page.dart';
import '../../widgets/bangumi_rich_text.dart';

@immutable
class ComposeEpisodeDiscussion {
  const ComposeEpisodeDiscussion(
    this.episode,
    this.comments,
    this.metadataError,
  );
  final SubjectEpisode episode;
  final List<CommunityReply> comments;
  final Object? metadataError;
}

class EpisodeCommentsPage extends StatelessWidget {
  const EpisodeCommentsPage({
    super.key,
    required this.episode,
    required this.repository,
  });
  final SubjectEpisode episode;
  final BangumiRepository repository;
  Future<ComposeEpisodeDiscussion> _load() async {
    Object? metadataError;
    final metadata =
        repository is EpisodeMetadataRepository
            ? (repository as EpisodeMetadataRepository)
                .fetchEpisode(episode.id)
                .catchError((Object e) {
                  metadataError = e;
                  return episode;
                })
            : Future.value(episode);
    final comments = repository.fetchEpisodeComments(episode.id);
    final results = await Future.wait<Object>([metadata, comments]);
    return ComposeEpisodeDiscussion(
      results[0] as SubjectEpisode,
      List.unmodifiable(results[1] as List<CommunityReply>),
      metadataError,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => CommentReadingPage<ComposeEpisodeDiscussion>(
    key: ValueKey('episode-comments:${episode.id}'),
    repository: repository,
    title:
        '${AppLocalizations.of(context).t('episodeDetail')} · ${episode.sort.toString().replaceAll(RegExp(r'\.0$'), '')}',
    target: ComposeCommentTarget.episode(episode.id, episode.title),
    load: _load,
    items: (data) => data.comments,
    sortable: true,
    onReact:
        (item, value) => repository.setEpisodeCommentReaction(item.id, value),
    header: (data) {
      final ep = data.episode;
      final s = AppLocalizations.of(context);
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ep.title, style: Theme.of(context).textTheme.headlineSmall),
            if (ep.name.isNotEmpty && ep.name != ep.title)
              Text(ep.name, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('${s.t('episodeNumber')}: ${ep.sort}'),
                Text(
                  '${s.t('airdate')}: ${ep.airdate.isEmpty ? '—' : ep.airdate}',
                ),
                Text(
                  '${s.t('duration')}: ${ep.duration.isEmpty ? '—' : ep.duration}',
                ),
                Text(
                  '${s.t('episodeKind')}: ${ep.type == 0 ? s.t('mainEpisode') : 'SP ${ep.type}'}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (data.metadataError != null)
              Text(
                s.t('episodeMetadataFailed'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (ep.description.isNotEmpty)
              BangumiRichText(ep.description)
            else if (data.metadataError == null)
              Text(s.t('episodeNoDescription')),
            const SizedBox(height: 16),
            const Divider(),
            Text(
              s.t('blogComments'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    },
  );
}
