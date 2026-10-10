import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/paged_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_footer.dart';
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
    immediate: true,
    key: const ValueKey('search-results'),
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
      key: const ValueKey('search-results'),
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
    this.immediate = false,
  });

  final BangumiRepository repository;
  final String query;
  final bool immediate;
  final int? type;

  @override
  State<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<_SearchResults> {
  Timer? _debounce;
  bool _waiting = true;
  String _activeQuery = '';
  late final PagedController<Subject> _results = PagedController(
    load:
        (offset) => searchPage(
          widget.repository,
          _activeQuery,
          type: widget.type,
          offset: offset,
        ),
    idOf: (subject) => subject.id,
  );
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _SearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query ||
        oldWidget.type != widget.type ||
        oldWidget.immediate != widget.immediate) {
      _schedule();
    }
  }

  void _schedule() {
    _debounce?.cancel();
    _waiting = true;
    void execute() {
      if (!mounted) return;
      _activeQuery = widget.query;
      setState(() => _waiting = false);
      _results.reset();
    }

    if (widget.immediate) {
      // State 初始化时不在 build 中触发 setState。
      _activeQuery = widget.query;
      _waiting = false;
      _results.reset();
    } else {
      _debounce = Timer(const Duration(milliseconds: 350), execute);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _results.dispose();
    super.dispose();
  }

  void _retry() {
    if (_results.error != null) invalidateRepositoryCache(widget.repository);
    _results.loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _results,
      builder: (context, _) {
        if (_waiting || (_results.loading && _results.items.isEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_results.error != null && _results.items.isEmpty) {
          return NetworkErrorView(error: _results.error!, onRetry: _retry);
        }
        final subjects = _results.items;
        if (subjects.isEmpty) return const Center(child: Text('没有找到相关条目'));
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 &&
                notification.metrics.extentAfter < 300 &&
                _results.error == null) {
              _results.loadMore();
            }
            return false;
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: subjects.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == subjects.length) {
                return PagedFooter(
                  loading: _results.loading,
                  hasMore: _results.hasMore,
                  error: _results.error,
                  onLoadMore: _retry,
                );
              }
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
                              memCacheWidth:
                                  (42 * MediaQuery.devicePixelRatioOf(context))
                                      .round(),
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
          ),
        );
      },
    );
  }
}
