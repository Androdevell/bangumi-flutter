import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/media/rich_image_policy.dart';
import '../core/network/app_image_cache.dart';
import '../core/localization/app_localizations.dart';
import 'image_viewer_page.dart';

class RichCommentImage extends StatefulWidget {
  const RichCommentImage({super.key, required this.uri, this.deferred = false});
  final Uri uri;
  final bool deferred;
  @override
  State<RichCommentImage> createState() => _RichCommentImageState();
}

class _RichCommentImageState extends State<RichCommentImage> {
  bool _once = false;
  int _revision = 0;

  Future<void> _retry(Uri uri) async {
    try {
      await AppImageCache.manager.removeFile(uri.toString());
      await createViewerImageProvider(
        uri.toString(),
        AppImageCache.manager,
      ).evict();
      if (mounted) setState(() => _revision++);
    } on Object {
      _showFailure();
    }
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showFailure();
      }
    } on Object {
      _showFailure();
    }
  }

  void _showFailure() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).t('operationFailed')),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant RichCommentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) {
      _once = false;
      _revision = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final uri = widget.uri.replace(scheme: 'https');
    if (!ImageUrlSafety.valid(uri)) return Text(strings.t('imageUnsafe'));
    return ListenableBuilder(
      listenable: RichImagePolicy.instance,
      builder: (context, _) {
        final policy = RichImagePolicy.instance;
        final blocked =
            policy.mode == ExternalImageMode.blocked &&
            !RichImagePolicy.trustedHosts.contains(uri.host);
        if (blocked || (!_once && (widget.deferred || !policy.allows(uri)))) {
          return Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(uri.host, style: Theme.of(context).textTheme.labelLarge),
                  if (!blocked)
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() => _once = true),
                          icon: const Icon(Icons.image_outlined),
                          label: Text(
                            strings.t(
                              widget.deferred ? 'imageMore' : 'loadImage',
                            ),
                          ),
                        ),
                        if (!widget.deferred)
                          TextButton(
                            onPressed: () => policy.allowHost(uri.host),
                            child: Text(strings.t('allowImageHost')),
                          ),
                      ],
                    )
                  else
                    Text(strings.t('imageBlocked')),
                ],
              ),
            ),
          );
        }
        return InkWell(
          onTap:
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder:
                      (_) => ImageViewerPage(
                        urls: [uri.toString()],
                        permission: policy,
                        allowed:
                            () =>
                                policy.mode != ExternalImageMode.blocked ||
                                RichImagePolicy.trustedHosts.contains(uri.host),
                      ),
                ),
              ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image(
              key: ValueKey('${uri}_$_revision'),
              image: createViewerImageProvider(
                uri.toString(),
                AppImageCache.manager,
              ),
              fit: BoxFit.contain,
              frameBuilder:
                  (_, child, frame, sync) =>
                      frame != null || sync
                          ? child
                          : const SizedBox(
                            height: 140,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
              errorBuilder:
                  (_, __, error) => Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${strings.t('imageFailed')} · ${uri.host}'),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () => _retry(uri),
                              icon: const Icon(Icons.refresh),
                              label: Text(strings.t('retry')),
                            ),
                            TextButton(
                              onPressed: () => _openExternal(uri),
                              child: Text(strings.t('externalImage')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
            ),
          ),
        );
      },
    );
  }
}

/// 评论图片设置；独立保存展开状态，不与父级列表的滚动位置共用缓存键。
class CommentImageSetting extends StatelessWidget {
  const CommentImageSetting({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: RichImagePolicy.instance,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final policy = RichImagePolicy.instance;
      return ExpansionTile(
        key: const PageStorageKey('comment-image-setting-expansion'),
        leading: const Icon(Icons.image_outlined),
        title: Text(strings.t('commentImages')),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Text(strings.t('imagePrivacy')),
          for (final mode in ExternalImageMode.values)
            RadioListTile<ExternalImageMode>(
              value: mode,
              groupValue: policy.mode,
              title: Text(
                strings.t(switch (mode) {
                  ExternalImageMode.onDemand => 'imageOnDemand',
                  ExternalImageMode.automatic => 'imageAutomatic',
                  ExternalImageMode.blocked => 'imageBlocked',
                }),
              ),
              onChanged: (v) {
                if (v != null) policy.setMode(v);
              },
            ),
          TextButton(
            onPressed: policy.resetHosts,
            child: Text(strings.t('resetImageHosts')),
          ),
        ],
      );
    },
  );
}
