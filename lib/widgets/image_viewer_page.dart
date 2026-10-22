import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/network/app_image_cache.dart';
import '../core/localization/app_localizations.dart';

/// 以视口坐标为唯一基准；缩放始终围绕锚点，边界按实际图片而非留白计算。
class ImageZoomController extends TransformationController {
  Size viewport = Size.zero;
  Size natural = Size.zero;
  double get scale => value.getMaxScaleOnAxis();
  void configure(Size size, {Size? image}) {
    final changed = viewport != size;
    viewport = size;
    if (image != null) natural = image;
    if (changed) reset();
  }

  void reset() => value = Matrix4.identity();
  void zoomAt(double target, Offset anchor) {
    final scene = toScene(anchor);
    final s = target.clamp(1.0, 8.0);
    value =
        Matrix4.identity()
          ..translate(anchor.dx - scene.dx * s, anchor.dy - scene.dy * s)
          ..scale(s);
    clampBounds();
  }

  void clampBounds() {
    if (viewport.isEmpty) return;
    final s = scale.clamp(1.0, 8.0);
    final fitted =
        natural.isEmpty
            ? viewport
            : applyBoxFit(BoxFit.contain, natural, viewport).destination;
    final origin = Offset(
      (viewport.width - fitted.width) / 2,
      (viewport.height - fitted.height) / 2,
    );
    double bound(double t, double start, double length, double available) =>
        length * s <= available
            ? (available - length * s) / 2 - start * s
            : t.clamp(available - (start + length) * s, -start * s);
    final p = value.getTranslation();
    value =
        Matrix4.identity()
          ..translate(
            bound(p.x, origin.dx, fitted.width, viewport.width),
            bound(p.y, origin.dy, fitted.height, viewport.height),
          )
          ..scale(s);
  }
}

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.urls,
    this.index = 0,
    this.permission,
    this.allowed,
  });
  final List<String> urls;
  final int index;
  final Listenable? permission;
  final bool Function()? allowed;
  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  final zoom = ImageZoomController();
  late int index = widget.index.clamp(0, math.max(0, widget.urls.length - 1));
  Offset anchor = Offset.zero;
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  void _watch(ImageProvider provider) {
    if (_provider == provider) return;
    _detach();
    _provider = provider;
    final stream = _stream = provider.resolve(const ImageConfiguration());
    _listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _stream != stream) return;
        zoom.configure(
          zoom.viewport,
          image: Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          ),
        );
        zoom.clampBounds();
      });
    });
    stream.addListener(_listener!);
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _provider = null;
  }

  void _change(int delta) {
    final next = index + delta;
    if (next < 0 || next >= widget.urls.length) return;
    _detach();
    zoom.natural = Size.zero;
    zoom.reset();
    setState(() => index = next);
  }

  @override
  void dispose() {
    _detach();
    zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    Widget content() => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${index + 1}/${widget.urls.length}'),
        actions: [
          IconButton(
            tooltip: s.t('imageExternal'),
            icon: const Icon(Icons.open_in_new),
            onPressed:
                widget.urls.isEmpty || widget.allowed?.call() == false
                    ? null
                    : () async {
                      try {
                        await launchUrl(
                          Uri.parse(widget.urls[index]),
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (_) {
                        /* 关闭或外部程序不可用不改变图片状态。 */
                      }
                    },
          ),
        ],
      ),
      body:
          widget.urls.isEmpty || widget.allowed?.call() == false
              ? Center(
                child: Text(
                  s.t('imageBlocked'),
                  style: const TextStyle(color: Colors.white),
                ),
              )
              : LayoutBuilder(
                builder: (context, box) {
                  final size = Size(box.maxWidth, box.maxHeight);
                  if (size != zoom.viewport) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) zoom.configure(size);
                    });
                  }
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onDoubleTapDown: (d) => anchor = d.localPosition,
                          onDoubleTap:
                              () => zoom.zoomAt(
                                zoom.scale > 1.05 ? 1 : 2.5,
                                anchor,
                              ),
                          child: InteractiveViewer(
                            transformationController: zoom,
                            minScale: 1,
                            maxScale: 8,
                            trackpadScrollCausesScale: true,
                            onInteractionEnd: (_) => zoom.clampBounds(),
                            child: SizedBox(
                              width: size.width,
                              height: size.height,
                              child: CachedNetworkImage(
                                imageUrl: widget.urls[index],
                                cacheManager: AppImageCache.manager,
                                memCacheWidth: 4096,
                                memCacheHeight: 4096,
                                imageBuilder: (_, provider) {
                                  _watch(provider);
                                  return Image(
                                    image: provider,
                                    fit: BoxFit.contain,
                                  );
                                },
                                placeholder:
                                    (_, __) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                errorWidget:
                                    (_, __, ___) => Center(
                                      child: FilledButton.tonalIcon(
                                        icon: const Icon(Icons.refresh),
                                        label: Text(s.t('retry')),
                                        onPressed: () async {
                                          try {
                                            await CachedNetworkImage.evictFromCache(
                                              widget.urls[index],
                                              cacheManager:
                                                  AppImageCache.manager,
                                            );
                                          } on Object {
                                            /* 保留重试入口，缓存失败不触发未处理异常。 */
                                          }
                                          _detach();
                                          if (mounted) setState(() {});
                                        },
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Material(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHigh
                                .withValues(alpha: .95),
                            borderRadius: BorderRadius.circular(32),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.urls.length > 1)
                                  IconButton(
                                    tooltip: s.t('previous'),
                                    onPressed:
                                        index > 0 ? () => _change(-1) : null,
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                IconButton(
                                  tooltip: s.t('imageZoomOut'),
                                  onPressed:
                                      () => zoom.zoomAt(
                                        zoom.scale / 1.4,
                                        size.center(Offset.zero),
                                      ),
                                  icon: const Icon(Icons.remove),
                                ),
                                IconButton(
                                  tooltip: s.t('imageFit'),
                                  onPressed: zoom.reset,
                                  icon: const Icon(Icons.fit_screen),
                                ),
                                ValueListenableBuilder<Matrix4>(
                                  valueListenable: zoom,
                                  builder:
                                      (_, __, ___) => SizedBox(
                                        width: 42,
                                        child: Text(
                                          '${(zoom.scale * 100).round()}%',
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                ),
                                IconButton(
                                  tooltip: s.t('imageZoomIn'),
                                  onPressed:
                                      () => zoom.zoomAt(
                                        zoom.scale * 1.4,
                                        size.center(Offset.zero),
                                      ),
                                  icon: const Icon(Icons.add),
                                ),
                                if (widget.urls.length > 1)
                                  IconButton(
                                    tooltip: s.t('next'),
                                    onPressed:
                                        index + 1 < widget.urls.length
                                            ? () => _change(1)
                                            : null,
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            () => Navigator.maybePop(context),
        const SingleActivator(LogicalKeyboardKey.digit0): zoom.reset,
        const SingleActivator(LogicalKeyboardKey.equal):
            () => zoom.zoomAt(
              zoom.scale * 1.4,
              zoom.viewport.center(Offset.zero),
            ),
        const SingleActivator(LogicalKeyboardKey.equal, shift: true):
            () => zoom.zoomAt(
              zoom.scale * 1.4,
              zoom.viewport.center(Offset.zero),
            ),
        const SingleActivator(LogicalKeyboardKey.numpadAdd):
            () => zoom.zoomAt(
              zoom.scale * 1.4,
              zoom.viewport.center(Offset.zero),
            ),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract):
            () => zoom.zoomAt(
              zoom.scale / 1.4,
              zoom.viewport.center(Offset.zero),
            ),
        const SingleActivator(LogicalKeyboardKey.minus):
            () => zoom.zoomAt(
              zoom.scale / 1.4,
              zoom.viewport.center(Offset.zero),
            ),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _change(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _change(1),
      },
      child: Focus(
        autofocus: true,
        child:
            widget.permission == null
                ? content()
                : ListenableBuilder(
                  listenable: widget.permission!,
                  builder: (_, __) => content(),
                ),
      ),
    );
  }
}
