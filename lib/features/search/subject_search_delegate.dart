import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/network/app_image_cache.dart';
import '../../data/bangumi_repository.dart';
import '../subject/subject_detail_page.dart';

class SubjectSearchDelegate extends SearchDelegate<void> {
  SubjectSearchDelegate({required this.repository, this.type});

  final BangumiRepository repository;
  final int? type;

  @override
  String get searchFieldLabel => '搜索条目';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: '清空',
        onPressed: () => query = '',
        icon: const Icon(Icons.close_rounded),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: '返回',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => _SearchResults(
    key: ValueKey(query.trim()),
    repository: repository,
    query: query.trim(),
    type: type,
  );

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      return const Center(child: Text('输入关键词开始搜索'));
    }
    return _SearchResults(
      key: ValueKey(query.trim()),
      repository: repository,
      query: query.trim(),
      type: type,
    );
  }
}

class _SearchResults extends StatefulWidget {
  const _SearchResults({
    super.key,
    required this.repository,
    required this.query,
    required this.type,
  });

  final BangumiRepository repository;
  final String query;
  final int? type;

  @override
  State<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<_SearchResults> {
  late final Future<List<Subject>> _future = widget.repository.searchSubjects(
    widget.query,
    type: widget.type,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Subject>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        final subjects = snapshot.data ?? const [];
        if (subjects.isEmpty) return const Center(child: Text('没有找到相关条目'));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: subjects.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final subject = subjects[index];
            return ListTile(
              leading: SizedBox(
                width: 42,
                height: 54,
                child:
                    subject.imageUrl.isEmpty
                        ? Icon(subject.symbol)
                        : ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: subject.imageUrl,
                            cacheManager: AppImageCache.manager,
                            fit: BoxFit.cover,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholderFadeInDuration: Duration.zero,
                            useOldImageOnUrlChange: true,
                            placeholder: (_, __) => Icon(subject.symbol),
                            errorWidget: (_, __, ___) => Icon(subject.symbol),
                          ),
                        ),
              ),
              title: Text(subject.title),
              subtitle: Text(
                subject.subtitle.isEmpty
                    ? subject.originalTitle
                    : subject.subtitle,
              ),
              trailing:
                  subject.score > 0
                      ? Text(subject.score.toStringAsFixed(1))
                      : null,
              onTap:
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder:
                          (_) => SubjectDetailPage(
                            subject: subject,
                            heroTag: 'search-${subject.id}',
                            repository: widget.repository,
                          ),
                    ),
                  ),
            );
          },
        );
      },
    );
  }
}
