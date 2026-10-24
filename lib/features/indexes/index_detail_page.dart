import 'package:flutter/material.dart';
import '../../data/bangumi_repository.dart';
import '../../domain/repositories/index_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/bangumi_rich_text.dart';
import '../../app/app_links.dart';
import '../../core/localization/app_localizations.dart';

class IndexDetailPage extends StatefulWidget {
  const IndexDetailPage({
    super.key,
    required this.id,
    required this.repository,
  });
  final int id;
  final BangumiRepository repository;
  @override
  State<IndexDetailPage> createState() => _IndexDetailPageState();
}

class _IndexDetailPageState extends State<IndexDetailPage> {
  Listenable? get _sessionChanges =>
      widget.repository is CollectionFeatureRepository
          ? (widget.repository as CollectionFeatureRepository)
              .collections
              .sessionChanges
          : null;
  void _sessionChanged() => _load(reset: true);
  Map<String, dynamic>? _info;
  final _entries = <Map<String, dynamic>>[];
  Object? _error;
  bool _busy = false, _more = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _sessionChanges?.addListener(_sessionChanged);
    _load(reset: true);
  }

  @override
  void dispose() {
    _sessionChanges?.removeListener(_sessionChanged);
    _generation++;
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy && !reset) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      if (reset) {
        _entries.clear();
        _info = null;
      }
    });
    try {
      final repo = widget.repository as IndexRepository;
      final info = _info ?? await repo.indexInfo(widget.id);
      final page = await repo.indexEntries(widget.id, offset: _entries.length);
      if (!mounted || generation != _generation) return;
      setState(() {
        _info = info;
        _entries.addAll(page.items);
        _more = page.hasMore;
      });
    } on Object catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${_info?['title'] ?? s.t('directory')}')),
      body: ContentFrame(
        maxWidth: 900,
        child: ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: _entries.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_info?['title'] ?? ''}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  BangumiRichText(
                    '${_info?['desc'] ?? _info?['description'] ?? ''}',
                  ),
                  const Divider(),
                ],
              );
            }
            if (index > _entries.length) {
              return Column(
                children: [
                  if (_error != null)
                    NetworkErrorView(error: _error!, onRetry: _load),
                  if (_busy) const Center(child: CircularProgressIndicator()),
                  if (!_busy && _error == null && _more)
                    TextButton(onPressed: _load, child: Text(s.t('loadMore'))),
                ],
              );
            }
            final item = _entries[index - 1];
            for (final (key, path) in [
              ('subject', 'subject'),
              ('character', 'character'),
              ('person', 'person'),
              ('episode', 'ep'),
              ('blog', 'blog'),
              ('groupTopic', 'group/topic'),
              ('subjectTopic', 'subject/topic'),
            ]) {
              if (item[key] is! Map) continue;
              final value = item[key] as Map;
              final id = value['id'];
              return Card.filled(
                child: ListTile(
                  title: Text(
                    '${value['nameCN'] ?? value['title'] ?? value['name'] ?? ''}',
                  ),
                  subtitle:
                      item['comment'] == ''
                          ? null
                          : BangumiRichText('${item['comment'] ?? ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap:
                      () => AppLinkDispatcher.open(
                        context,
                        Uri.https('bgm.tv', '/$path/$id'),
                      ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
