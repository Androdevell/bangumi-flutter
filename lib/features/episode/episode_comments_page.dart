import 'package:flutter/material.dart';
import '../../core/community_models.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/subject_detail_models.dart';
import '../../data/bangumi_repository.dart';
import '../../domain/use_cases/comment_submit_use_case.dart';
import '../community/comment_reading_page.dart';

class EpisodeCommentsPage extends StatelessWidget {
  const EpisodeCommentsPage({
    super.key,
    required this.episode,
    required this.repository,
  });
  final SubjectEpisode episode;
  final BangumiRepository repository;
  @override
  Widget build(
    BuildContext context,
  ) => CommentReadingPage<List<CommunityReply>>(
    key: ValueKey('episode-comments:${episode.id}'),
    repository: repository,
    title:
        '${AppLocalizations.of(context).t('episodeComment')} · ${episode.sort.toString().replaceAll('.0', '')}',
    target: ComposeCommentTarget.episode(episode.id, episode.title),
    load: () => repository.fetchEpisodeComments(episode.id),
    items: (items) => items,
    onReact:
        (item, value) => repository.setEpisodeCommentReaction(item.id, value),
    header:
        (_) => Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            episode.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
  );
}
