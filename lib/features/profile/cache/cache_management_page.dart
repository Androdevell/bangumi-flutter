import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../domain/models/cache_usage.dart';
import '../../../widgets/common.dart';
import 'cache_controller.dart';

String formatCacheBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class CacheManagementPage extends StatefulWidget {
  const CacheManagementPage({super.key, required this.service});
  final CacheMaintenance service;
  @override
  State<CacheManagementPage> createState() => _CacheManagementPageState();
}

class _CacheManagementPageState extends State<CacheManagementPage> {
  late final _controller = CacheController(widget.service);
  @override
  void initState() {
    super.initState();
    unawaited(_controller.dispatch(const LoadCacheUsage()));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _clear(Set<CacheCategory> categories) async {
    final s = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(s.t('cacheConfirm')),
            content: SingleChildScrollView(
              child: Text(
                '${categories.map((e) => s.t('cacheTitle_${e.name}')).join('、')}\n\n${s.t('cachePreserved')}',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(s.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(s.t('clearCache')),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    await _controller.clear(categories);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final state = _controller.state;
        final busy = state.loading || state.clearing;
        final available =
            state.usage
                .where((e) => !e.unavailable)
                .map((e) => e.category)
                .toList();
        final allSelected =
            available.isNotEmpty && available.every(state.selected.contains);
        final disk = state.usage
            .where((e) => e.category != CacheCategory.memory)
            .fold(0, (sum, e) => sum + e.bytes);
        final selectedBytes = state.usage
            .where(
              (e) =>
                  state.selected.contains(e.category) &&
                  e.category != CacheCategory.memory,
            )
            .fold(0, (sum, e) => sum + e.reclaimableBytes);
        final memoryBytes = state.usage
            .where(
              (e) =>
                  e.category == CacheCategory.memory &&
                  state.selected.contains(e.category),
            )
            .fold(0, (sum, e) => sum + e.bytes);
        return Scaffold(
          appBar: AppBar(
            title: Text(s.t('cacheManagement')),
            actions: [
              IconButton(
                key: const ValueKey('cache-refresh'),
                tooltip: s.t('refresh'),
                onPressed:
                    busy
                        ? null
                        : () => _controller.dispatch(const LoadCacheUsage()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                key: const ValueKey('cache-clear-selected'),
                onPressed:
                    busy || state.selected.isEmpty
                        ? null
                        : () => _clear(state.selected),
                icon:
                    busy
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.cleaning_services_outlined),
                label: Text(
                  '${s.t(state.clearing ? 'cacheClearing' : 'cacheClearSelected')} · ${s.t('cacheEstimated')} ${formatCacheBytes(selectedBytes)}${memoryBytes > 0 ? ' · ${s.t('cacheMemoryReclaim')} ${formatCacheBytes(memoryBytes)}' : ''}',
                ),
              ),
            ),
          ),
          body: ContentFrame(
            maxWidth: 840,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SurfaceBlock(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.t('cacheDiskUsage'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.loading && state.usage.isEmpty
                            ? '—'
                            : formatCacheBytes(disk),
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(s.t('cachePreserved')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.t('cacheCategories'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed:
                          busy
                              ? null
                              : () {
                                final all = allSelected;
                                for (final category in available) {
                                  unawaited(
                                    _controller.dispatch(
                                      SelectCacheCategory(category, !all),
                                    ),
                                  );
                                }
                              },
                      child: Text(
                        s.t(allSelected ? 'cacheSelectNone' : 'cacheSelectAll'),
                      ),
                    ),
                  ],
                ),
                if (busy) const LinearProgressIndicator(),
                if (state.failed) Text(s.t('cacheReadFailed')),
                if (state.result case final result?)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      [
                        s.t(
                          result.failed.isEmpty && result.busy.isEmpty
                              ? 'cacheManagementDone'
                              : 'cachePartial',
                        ),
                        '${s.t('cacheReduction')}: ${formatCacheBytes(state.diskReduction)}',
                        if (result.busy.isNotEmpty)
                          '${s.t('cacheRetained')}: ${result.busy.map((e) => s.t('cacheTitle_${e.name}')).join('、')}',
                        if (result.failed.isNotEmpty)
                          '${s.t('cacheFailedItems')}: ${result.failed.map((e) => s.t('cacheTitle_${e.name}')).join('、')}',
                      ].join('\n'),
                    ),
                  ),
                for (final usage in state.usage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SurfaceBlock(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                key: ValueKey(
                                  'cache-select-${usage.category.name}',
                                ),
                                value: state.selected.contains(usage.category),
                                onChanged:
                                    busy || usage.unavailable
                                        ? null
                                        : (value) => _controller.dispatch(
                                          SelectCacheCategory(
                                            usage.category,
                                            value!,
                                          ),
                                        ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.t('cacheTitle_${usage.category.name}'),
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      s.t(
                                        'cacheDescription_${usage.category.name}',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                usage.unavailable
                                    ? s.t('cacheUnavailable')
                                    : formatCacheBytes(usage.bytes),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                '${usage.files} ${s.t(usage.category == CacheCategory.memory ? 'cacheMemoryItems' : 'cacheFiles')}',
                              ),
                              if (usage.protectedFiles > 0)
                                Text(
                                  '${s.t('cacheProtected')}: ${usage.protectedFiles} (${formatCacheBytes(usage.protectedBytes)})',
                                ),
                              TextButton(
                                key: ValueKey(
                                  'cache-clear-${usage.category.name}',
                                ),
                                onPressed:
                                    busy || usage.unavailable
                                        ? null
                                        : () => _clear({usage.category}),
                                child: Text(s.t('clearCache')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(s.t('cacheRebuildHint')),
              ],
            ),
          ),
        );
      },
    );
  }
}
