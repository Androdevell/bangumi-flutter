import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/network/app_image_cache.dart';
import '../../core/localization/app_localizations.dart';
import '../../data/bangumi_repository.dart';
import '../../domain/models/group_models.dart';
import '../../domain/repositories/group_repository.dart';
import '../../widgets/bangumi_rich_text.dart';
import '../../widgets/common.dart';
import '../rakuen/topic_detail_page.dart';
import 'group_controller.dart';

class GroupDirectoryPage extends StatefulWidget {
  const GroupDirectoryPage({
    super.key,
    required this.repository,
    required this.groups,
  });
  final BangumiRepository repository;
  final GroupRepository groups;
  @override
  State<GroupDirectoryPage> createState() => _GroupDirectoryPageState();
}

class _GroupDirectoryPageState extends State<GroupDirectoryPage> {
  late final _model = GroupDirectoryController(widget.groups)..load();
  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final state = _model.state;
      return ContentFrame(
        maxWidth: 980,
        child: RefreshIndicator(
          onRefresh: () => _model.load(reset: true),
          child: ListView(
            key: PageStorageKey('groups:${_model.mode}:${_model.sort}'),
            padding: const EdgeInsets.all(20),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in ['all', 'joined'])
                    ChoiceChip(
                      label: Text(
                        strings.t(
                          mode == 'all' ? 'discoverGroups' : 'joinedGroups',
                        ),
                      ),
                      selected: _model.mode == mode,
                      onSelected: (_) {
                        if (mode == 'joined' && !widget.groups.isLoggedIn) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(strings.t('loginRequired'))),
                          );
                          return;
                        }
                        _model.select(mode: mode);
                      },
                    ),
                  DropdownButton<String>(
                    value: _model.sort,
                    items: [
                      for (final entry
                          in {
                            'updated': 'groupUpdated',
                            'members': 'groupMembers',
                            'created': 'groupCreated',
                          }.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(strings.t(entry.value)),
                        ),
                    ],
                    onChanged: (value) => _model.select(sort: value),
                  ),
                ],
              ),
              if (state.loading) const LinearProgressIndicator(minHeight: 2),
              if (state.error != null)
                TextButton.icon(
                  onPressed: () => _model.load(reset: state.items.isEmpty),
                  icon: const Icon(Icons.refresh),
                  label: Text('${strings.t('retry')} · ${state.error}'),
                ),
              if (!state.loading && state.items.isEmpty && state.error == null)
                EmptyView(message: strings.t('noGroups')),
              for (final group in state.items)
                Card.outlined(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: _GroupIcon(group.icon),
                    title: Text(group.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.description.replaceAll(
                            RegExp(r'\[[^\]]*\]'),
                            '',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${strings.t('groupMembers')} ${group.members} · ${strings.t('groupTopics')} ${group.topics}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder:
                                (_) => GroupDetailPage(
                                  group: group,
                                  groups: widget.groups,
                                  repository: widget.repository,
                                ),
                          ),
                        ),
                  ),
                ),
              if (state.hasMore && !state.loading)
                TextButton(
                  onPressed: _model.load,
                  child: Text(strings.t('loadMore')),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _GroupIcon extends StatelessWidget {
  const _GroupIcon(this.url);
  final String url;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox.square(
      dimension: 48,
      child:
          url.isEmpty
              ? const Icon(Icons.groups_outlined)
              : CachedNetworkImage(
                imageUrl: url,
                cacheManager: AppImageCache.manager,
                memCacheWidth: 144,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const Icon(Icons.groups_outlined),
              ),
    ),
  );
}

class GroupDetailPage extends StatefulWidget {
  const GroupDetailPage({
    super.key,
    required this.group,
    required this.groups,
    required this.repository,
  });
  final ComposeGroup group;
  final GroupRepository groups;
  final BangumiRepository repository;
  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  late final GroupDetailController _model;
  @override
  void initState() {
    super.initState();
    _model = GroupDetailController(widget.groups, widget.group.name)..refresh();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final state = _model.state;
        final group = state.group;
        return Scaffold(
          appBar: AppBar(
            title: Text(group?.title ?? strings.t('groupDirectory')),
          ),
          body: ContentFrame(
            maxWidth: 980,
            child: RefreshIndicator(
              onRefresh: _model.refresh,
              child: ListView(
                padding: const EdgeInsets.all(20),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (state.loading || state.loadingDetail)
                    const LinearProgressIndicator(minHeight: 2),
                  if (state.detailError != null)
                    TextButton(
                      onPressed: _model.refresh,
                      child: Text(
                        '${strings.t('retry')} · ${state.detailError}',
                      ),
                    ),
                  if (group != null)
                    SurfaceBlock(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _GroupIcon(group.icon),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  group.title,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          BangumiRichText(group.description),
                          const SizedBox(height: 12),
                          Text(
                            '${strings.t('groupMembers')} ${group.members} · ${strings.t('groupTopics')} ${group.topics}',
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (state.error != null)
                    TextButton(
                      onPressed: _model.refresh,
                      child: Text('${strings.t('retry')} · ${state.error}'),
                    ),
                  for (final topic in state.topics)
                    Card.outlined(
                      child: ListTile(
                        title: Text(topic.title),
                        subtitle: Text(
                          '${topic.creatorName} · ${topic.replies}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap:
                            () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder:
                                    (_) => TopicDetailPage(
                                      topic: topic,
                                      repository: widget.repository,
                                    ),
                              ),
                            ),
                      ),
                    ),
                  if (!state.loading && !state.loadingDetail && state.hasMore)
                    TextButton(
                      onPressed: _model.loadMore,
                      child: Text(strings.t('loadMore')),
                    ),
                  if (!state.loading &&
                      state.topics.isEmpty &&
                      state.error == null)
                    EmptyView(message: strings.t('noTopics')),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
