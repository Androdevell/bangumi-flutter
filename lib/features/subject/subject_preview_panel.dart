import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/models.dart';
import '../../core/network/app_image_cache.dart';
import '../../core/network/third_party_preview_service.dart';
import '../../core/subject_detail_models.dart';
import '../../widgets/common.dart';
import '../../widgets/third_party_preview_setting.dart';
import '../../widgets/image_viewer_page.dart';

class SubjectPreviewPanel extends StatefulWidget {
  const SubjectPreviewPanel({
    super.key,
    required this.subject,
    required this.service,
  });
  final Subject subject;
  final ThirdPartyPreviewService? service;

  @override
  State<SubjectPreviewPanel> createState() => _SubjectPreviewPanelState();
}

class _SubjectPreviewPanelState extends State<SubjectPreviewPanel> {
  TabController? _tabs;
  Future<List<SubjectPreview>>? _photos;

  @override
  void initState() {
    super.initState();
    widget.service?.addListener(_permissionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabs = DefaultTabController.maybeOf(context);
    if (_tabs != tabs) {
      _tabs?.removeListener(_tabChanged);
      _tabs = tabs;
      _tabs?.addListener(_tabChanged);
    }
    _ensurePhotos();
  }

  @override
  void didUpdateWidget(covariant SubjectPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.subject.id != widget.subject.id) {
      oldWidget.service?.removeListener(_permissionChanged);
      widget.service?.addListener(_permissionChanged);
      _photos = null;
      _ensurePhotos();
    }
  }

  void _ensurePhotos() {
    if (widget.service?.enabled == true &&
        (_tabs == null || _tabs!.index == 2)) {
      _photos ??= widget.service!.fetch(widget.subject);
    }
  }

  void _tabChanged() {
    if (mounted && _photos == null && _tabs?.index == 2) {
      setState(_ensurePhotos);
    }
  }

  void _permissionChanged() {
    if (!mounted) return;
    setState(() {
      _photos = null;
      _ensurePhotos();
    });
  }

  @override
  void dispose() {
    _tabs?.removeListener(_tabChanged);
    widget.service?.removeListener(_permissionChanged);
    super.dispose();
  }

  Future<void> _openBrowser() async {
    if (widget.service?.enabled != true) return;
    try {
      final opened = await launchUrl(
        Uri.https('www.douban.com', '/search', {
          'cat': '1002',
          'q': widget.subject.title,
        }),
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } on Object {
      /* 由界面统一提示，避免输出包含作品标题的 URL。 */
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).t('previewUnavailable')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final service = widget.service;
    if (service == null || !service.enabled) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EmptyView(message: strings.t('previewDisabled')),
          if (service != null) ThirdPartyPreviewSetting(service: service),
        ],
      );
    }
    if (!{2, 6}.contains(widget.subject.type)) {
      return EmptyView(message: strings.t('previewUnsupported'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(strings.t('previewSource')),
              TextButton.icon(
                onPressed: _openBrowser,
                icon: const Icon(Icons.open_in_new),
                label: Text(strings.t('previewBrowser')),
              ),
              IconButton(
                tooltip: strings.t('previewRetry'),
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  setState(() {
                    _photos = service.fetch(widget.subject, refresh: true);
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<SubjectPreview>>(
            future: _photos,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return LoadingView(label: strings.t('previewLoading'));
              }
              if (snapshot.hasError) {
                final error = snapshot.error;
                final key =
                    error is PreviewException
                        ? switch (error.failure) {
                          PreviewFailure.unavailable => 'previewUnavailable',
                          PreviewFailure.invalidResponse => 'previewInvalid',
                          _ => 'previewFailed',
                        }
                        : 'previewFailed';
                return EmptyView(message: strings.t(key));
              }
              final items = snapshot.data ?? const <SubjectPreview>[];
              if (items.isEmpty) {
                return EmptyView(message: strings.t('previewEmpty'));
              }
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.55,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder:
                                  (_) => ImageViewerPage(
                                    urls:
                                        items
                                            .map(
                                              (p) =>
                                                  p.largeImageUrl.isEmpty
                                                      ? p.imageUrl
                                                      : p.largeImageUrl,
                                            )
                                            .toList(),
                                    index: index,
                                    permission: service,
                                    allowed: () => service.enabled,
                                  ),
                            ),
                          ),
                      child: _PreviewImage(
                        url: item.imageUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PreviewImage extends StatefulWidget {
  const _PreviewImage({required this.url, required this.fit});
  final String url;
  final BoxFit fit;

  @override
  State<_PreviewImage> createState() => _PreviewImageState();
}

class _PreviewImageState extends State<_PreviewImage> {
  int _revision = 0;
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await CachedNetworkImage.evictFromCache(
        widget.url,
        cacheManager: AppImageCache.manager,
      );
      if (mounted) setState(() => _revision++);
    } on Object {
      // 清除失败仍保持局部错误态，允许稍后重试，不触发整页刷新。
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => CachedNetworkImage(
    key: ValueKey('${widget.url}-$_revision'),
    imageUrl: widget.url,
    cacheManager: AppImageCache.manager,
    fit: widget.fit,
    placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
    errorWidget:
        (_, __, ___) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image_not_supported_outlined),
              Text(AppLocalizations.of(context).t('imageFailed')),
              TextButton.icon(
                onPressed: _retrying ? null : _retry,
                icon: const Icon(Icons.refresh),
                label: Text(AppLocalizations.of(context).t('retry')),
              ),
            ],
          ),
        ),
  );
}
