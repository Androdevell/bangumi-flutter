import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models.dart';
import '../../core/paged_controller.dart';
import '../../core/localization/app_localizations.dart';
import '../../data/bangumi_repository.dart';
import '../../domain/repositories/tag_repository.dart';
import '../../widgets/subject_card.dart';
import '../../widgets/common.dart';
import '../subject/subject_navigation.dart';

class TagPage extends StatefulWidget {
  const TagPage({super.key, required this.query, required this.repository});
  final ComposeTagQuery query;
  final BangumiRepository repository;
  @override
  State<TagPage> createState() => _TagPageState();
}

class _TagPageState extends State<TagPage> {
  late final pages = PagedController<Subject>(
    load:
        (cursor) => (widget.repository as TagRepository).tagPage(
          widget.query,
          cursor + 1,
        ),
    idOf: (v) => v.id,
    pageBased: true,
  );
  @override
  void initState() {
    super.initState();
    if (widget.repository is TagRepository) pages.reset();
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('# ${widget.query.tag}')),
      body:
          widget.repository is! TagRepository
              ? Center(child: Text(s.t('tagUnavailable')))
              : ListenableBuilder(
                listenable: pages,
                builder:
                    (_, __) => CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverGrid.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 220,
                                  childAspectRatio: .6,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                ),
                            itemCount: pages.items.length,
                            itemBuilder: (context, index) {
                              final subject = pages.items[index];
                              final hero =
                                  'tag:${widget.query.type}:${widget.query.tag}:${subject.id}';
                              return SubjectCard(
                                subject: subject,
                                heroTag: hero,
                                onTap:
                                    () => openSubjectDetails(
                                      context,
                                      subject: subject,
                                      repository: widget.repository,
                                      heroTag: hero,
                                    ),
                              );
                            },
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              if (pages.error != null)
                                NetworkErrorView(
                                  error: pages.error!,
                                  onRetry: pages.loadMore,
                                ),
                              if (pages.loading)
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              if (pages.hasMore && !pages.loading)
                                TextButton(
                                  onPressed: pages.loadMore,
                                  child: Text(s.t('loadMore')),
                                ),
                              TextButton(
                                onPressed:
                                    () => launchUrl(
                                      Uri(
                                        scheme: 'https',
                                        host: 'bgm.tv',
                                        pathSegments: [
                                          switch (widget.query.type) {
                                            1 => 'book',
                                            3 => 'music',
                                            4 => 'game',
                                            6 => 'real',
                                            _ => 'anime',
                                          },
                                          'tag',
                                          widget.query.tag,
                                        ],
                                      ),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                child: Text(s.t('tagWebsite')),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
              ),
    );
  }
}
