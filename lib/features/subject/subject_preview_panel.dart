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
                          () => showDialog<void>(
                            context: context,
                            builder:
                                (context) => Dialog.fullscreen(
                                  child: ListenableBuilder(
                                    listenable: service,
                                    builder:
                                        (context, _) => Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            if (service.enabled)
                                              InteractiveViewer(
                                                minScale: 0.5,
                                                maxScale: 5,
                                                child: _PreviewImage(
                                                  url: item.largeImageUrl,
                                                  fit: BoxFit.contain,
                                                ),
                                              )
                                            else
                                              EmptyView(
                                                message: strings.t(
                                                  'previewDisabled',
                                                ),
                                              ),
                                            Positioned(
                                              top: 12,
                                              right: 12,
                                              child: SafeArea(
                                                child: IconButton.filledTonal(
                                                  tooltip: strings.t(
                                                    'previewClose',
                                                  ),
                                                  onPressed:
                                                      () => Navigator.pop(
                                                        context,
                                                      ),
                                                  icon: const Icon(Icons.close),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
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

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.url, required this.fit});
  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => CachedNetworkImage(
    imageUrl: url,
    cacheManager: AppImageCache.manager,
    httpHeaders: const {
      'Referer': 'https://m.douban.com/',
      'User-Agent': 'Mozilla/5.0',
    },
    fit: fit,
    placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
    errorWidget:
        (_, __, ___) =>
            const Center(child: Icon(Icons.image_not_supported_outlined)),
  );
}
