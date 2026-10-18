import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/localization/app_localizations.dart';

Future<Uint8List?> cropAvatar(BuildContext context, Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width <= 0 ||
        descriptor.height <= 0 ||
        descriptor.width * descriptor.height > 24 * 1024 * 1024) {
      throw const FormatException('Image pixel limit');
    }
    final factor = math.min(
      1.0,
      1536 / math.max(descriptor.width, descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * factor).round(),
      targetHeight: (descriptor.height * factor).round(),
    );
    image = (await codec.getNextFrame()).image;
    if (!context.mounted) return null;
    return await showDialog<Uint8List>(
      context: context,
      builder: (_) => _AvatarCropDialog(image!),
    );
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

class _AvatarCropDialog extends StatefulWidget {
  const _AvatarCropDialog(this.image);
  final ui.Image image;
  @override
  State<_AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<_AvatarCropDialog> {
  double _x = .5, _y = .5, _zoom = 1;
  bool _busy = false;
  Rect get _source {
    final size = math.min(widget.image.width, widget.image.height) / _zoom;
    return Rect.fromLTWH(
      (widget.image.width - size) * _x,
      (widget.image.height - size) * _y,
      size,
      size,
    );
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      widget.image,
      _source,
      const Rect.fromLTWH(0, 0, 512, 512),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(512, 512);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (mounted && data != null) {
        Navigator.pop(context, data.buffer.asUint8List());
      }
    } finally {
      image.dispose();
      picture.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(strings.t('cropAvatar')),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 240,
                child: CustomPaint(
                  painter: _AvatarPainter(widget.image, _source),
                ),
              ),
              Slider(
                value: _zoom,
                min: 1,
                max: 3,
                onChanged:
                    _busy ? null : (value) => setState(() => _zoom = value),
              ),
              Slider(
                value: _x,
                onChanged: _busy ? null : (value) => setState(() => _x = value),
              ),
              Slider(
                value: _y,
                onChanged: _busy ? null : (value) => setState(() => _y = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(strings.t('cancel')),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: Text(strings.t('cropConfirm')),
        ),
      ],
    );
  }
}

class _AvatarPainter extends CustomPainter {
  const _AvatarPainter(this.image, this.source);
  final ui.Image image;
  final Rect source;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
    image,
    source,
    Offset.zero & size,
    Paint()..filterQuality = FilterQuality.high,
  );
  @override
  bool shouldRepaint(covariant _AvatarPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.source != source;
}
