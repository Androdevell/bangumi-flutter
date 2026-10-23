import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/network/app_image_cache.dart';
import '../core/localization/app_localizations.dart';
import '../core/media/image_save_service.dart';

/// 单一路径、等比且禁止放大解码；预览和尺寸监听共用同一个缓存键。
ImageProvider createViewerImageProvider(String url, BaseCacheManager cache) =>
    ResizeImage(
      CachedNetworkImageProvider(url, cacheManager: cache),
      width: 2048,
      height: 2048,
      policy: ResizeImagePolicy.fit,
    );

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
    this.cacheManager,
  });
  final List<String> urls;
  final int index;
  final Listenable? permission;
  final bool Function()? allowed;
  final BaseCacheManager? cacheManager;
  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage>
    with SingleTickerProviderStateMixin {
  final zoom = ImageZoomController();
  BaseCacheManager get _cache => widget.cacheManager ?? AppImageCache.manager;
  late final AnimationController _animation;
  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(_animateZoom);
  }

  void _animateZoom() {
    final tween = _zoomTween;
    if (tween != null) {
      zoom.value = tween.transform(
        Curves.easeOutCubic.transform(_animation.value),
      );
    }
  }

  Matrix4Tween? _zoomTween;
  bool _saving = false;
  Offset _gestureStart = Offset.zero;
  double _swipeDistance = 0;
  bool _swipeEligible = false;
  Matrix4 _gestureMatrix = Matrix4.identity();
  Offset _gestureScene = Offset.zero;
  int _gesturePointers = 0;
  double _gestureScale = 1;
  bool get _allowed => mounted && widget.allowed?.call() != false;

  void _zoomTo(double scale, Offset point) {
    _animation.stop();
    final start = Matrix4.copy(zoom.value);
    zoom.zoomAt(scale, point);
    if (MediaQuery.disableAnimationsOf(context)) return;
    _zoomTween = Matrix4Tween(begin: start, end: Matrix4.copy(zoom.value));
    zoom.value = start;
    _animation.forward(from: 0);
  }

  void _resetZoom() {
    _animation.stop();
    zoom.reset();
  }

  Future<void> _save() async {
    if (_saving || !_allowed || widget.urls.isEmpty) return;
    final url = widget.urls[index];
    setState(() => _saving = true);
    String? message;
    try {
      if (await ImageSaveService(
        fetch: (url) => _cache.getSingleFile(url),
      ).save(url, allowed: () => _allowed)) {
        message = 'imageSaved';
      }
    } on Object {
      message = 'imageSaveFailed';
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).t(message))),
          );
        }
      }
    }
  }

  Future<void> _imageActions() async {
    if (!_allowed || _saving) return;
    final s = AppLocalizations.of(context);
    final save = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xff202020),
      builder:
          (context) => SafeArea(
            child: ListTile(
              textColor: Colors.white,
              iconColor: Colors.white,
              leading: const Icon(Icons.download_outlined),
              title: Text(s.t('imageSave')),
              onTap: () => Navigator.pop(context, true),
            ),
          ),
    );
    if (save == true) await _save();
  }

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
    _listener = ImageStreamListener(
      (info, _) {
        final imageSize = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        info.dispose();
        if (!mounted) return;
        if (zoom.natural == imageSize) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _stream != stream) return;
          zoom.configure(zoom.viewport, image: imageSize);
          zoom.clampBounds();
        });
      },
      onError: (Object _, StackTrace? __) {
        /* 主图的 errorBuilder 提供重试。 */
      },
    );
    stream.addListener(_listener!);
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _provider = null;
  }

  Widget _image(AppLocalizations strings) {
    final url = widget.urls[index];
    final provider = createViewerImageProvider(url, _cache);
    _watch(provider);
    return Image(
      key: ValueKey(url),
      image: provider,
      fit: BoxFit.contain,
      frameBuilder:
          (_, child, frame, synchronous) =>
              synchronous || frame != null
                  ? child
                  : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
      errorBuilder:
          (_, _, _) => Center(
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.refresh),
              label: Text(strings.t('retry')),
              onPressed: () async {
                try {
                  await provider.evict();
                  await CachedNetworkImage.evictFromCache(
                    url,
                    cacheManager: _cache,
                  );
                } on Object {
                  /* 缓存失败不触发未处理异常。 */
                }
                if (mounted && widget.urls[index] == url) {
                  _detach();
                  setState(() {});
                }
              },
            ),
          ),
    );
  }

  void _change(int delta) {
    final next = index + delta;
    if (next < 0 || next >= widget.urls.length) return;
    _animation.stop();
    _detach();
    zoom.natural = Size.zero;
    zoom.reset();
    setState(() => index = next);
  }

  @override
  void dispose() {
    _animation.dispose();
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
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.black,
          systemNavigationBarColor: Colors.black,
        ),
        title: Text(
          '${widget.urls.isEmpty ? 0 : index + 1}/${widget.urls.length}',
        ),
        actions: [
          IconButton(
            tooltip: s.t('imageSave'),
            onPressed:
                _saving || widget.urls.isEmpty || !_allowed ? null : _save,
            icon:
                _saving
                    ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Icon(Icons.download_outlined),
          ),
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
                      if (mounted) {
                        _animation.stop();
                        zoom.configure(size);
                      }
                    });
                  }
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Listener(
                          onPointerSignal: (event) {
                            if (event is PointerScrollEvent) {
                              GestureBinding.instance.pointerSignalResolver
                                  .register(event, (_) {
                                    _animation.stop();
                                    zoom.zoomAt(
                                      zoom.scale *
                                          math.exp(-event.scrollDelta.dy / 200),
                                      event.localPosition,
                                    );
                                  });
                            }
                          },
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPress: _imageActions,
                            onSecondaryTap: _imageActions,
                            onDoubleTapDown: (d) => anchor = d.localPosition,
                            onDoubleTap:
                                () => _zoomTo(
                                  zoom.scale > 1.05 ? 1 : 2.5,
                                  anchor,
                                ),
                            onScaleStart: (details) {
                              _animation.stop();
                              _gestureStart = details.focalPoint;
                              _gestureMatrix = Matrix4.copy(zoom.value);
                              _gestureScene = zoom.toScene(
                                details.localFocalPoint,
                              );
                              _gesturePointers = details.pointerCount;
                              _gestureScale = 1;
                              _swipeDistance = 0;
                              _swipeEligible = zoom.scale <= 1.05;
                            },
                            onScaleUpdate: (details) {
                              if (_gesturePointers != details.pointerCount) {
                                _gesturePointers = details.pointerCount;
                                _gestureMatrix = Matrix4.copy(zoom.value);
                                _gestureScene = zoom.toScene(
                                  details.localFocalPoint,
                                );
                                _gestureScale = details.scale;
                                _swipeEligible = false;
                                return;
                              }
                              final scale = (_gestureMatrix
                                          .getMaxScaleOnAxis() *
                                      details.scale /
                                      _gestureScale)
                                  .clamp(1.0, 8.0);
                              zoom.value =
                                  Matrix4.identity()
                                    ..translate(
                                      details.localFocalPoint.dx -
                                          _gestureScene.dx * scale,
                                      details.localFocalPoint.dy -
                                          _gestureScene.dy * scale,
                                    )
                                    ..scale(scale);
                              zoom.clampBounds();
                              _swipeDistance =
                                  details.focalPoint.dx - _gestureStart.dx;
                              if (details.pointerCount > 1 ||
                                  zoom.scale > 1.05) {
                                _swipeEligible = false;
                              }
                            },
                            onScaleEnd: (details) {
                              final velocity =
                                  details.velocity.pixelsPerSecond.dx;
                              if (_swipeEligible &&
                                  zoom.scale <= 1.05 &&
                                  _swipeDistance.abs() > 60 &&
                                  velocity.abs() > 500) {
                                _change(velocity < 0 ? 1 : -1);
                              }
                            },
                            child: ClipRect(
                              child: ValueListenableBuilder<Matrix4>(
                                key: const ValueKey('viewer-transform'),
                                valueListenable: zoom,
                                builder:
                                    (_, matrix, child) => Transform(
                                      transform: matrix,
                                      child: child,
                                    ),
                                child: SizedBox(
                                  width: size.width,
                                  height: size.height,
                                  child: RepaintBoundary(child: _image(s)),
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
                            color: const Color(0xee202020),
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
                                      () => _zoomTo(
                                        zoom.scale / 1.4,
                                        size.center(Offset.zero),
                                      ),
                                  icon: const Icon(Icons.remove),
                                ),
                                IconButton(
                                  tooltip: s.t('imageFit'),
                                  onPressed: _resetZoom,
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
                                      () => _zoomTo(
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
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.white,
          brightness: Brightness.dark,
        ),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape):
              () => Navigator.maybePop(context),
          const SingleActivator(LogicalKeyboardKey.digit0): _resetZoom,
          const SingleActivator(LogicalKeyboardKey.equal):
              () =>
                  _zoomTo(zoom.scale * 1.4, zoom.viewport.center(Offset.zero)),
          const SingleActivator(LogicalKeyboardKey.equal, shift: true):
              () =>
                  _zoomTo(zoom.scale * 1.4, zoom.viewport.center(Offset.zero)),
          const SingleActivator(LogicalKeyboardKey.numpadAdd):
              () =>
                  _zoomTo(zoom.scale * 1.4, zoom.viewport.center(Offset.zero)),
          const SingleActivator(LogicalKeyboardKey.numpadSubtract):
              () =>
                  _zoomTo(zoom.scale / 1.4, zoom.viewport.center(Offset.zero)),
          const SingleActivator(LogicalKeyboardKey.minus):
              () =>
                  _zoomTo(zoom.scale / 1.4, zoom.viewport.center(Offset.zero)),
          const SingleActivator(LogicalKeyboardKey.arrowLeft):
              () => _change(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight):
              () => _change(1),
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
      ),
    );
  }
}
