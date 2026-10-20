import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 先检查原始像素，再以缩略尺寸解码；仅返回可重建的小型 PNG。
Future<Uint8List> safeImageThumbnail(
  Uint8List bytes, {
  int dimension = 256,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    if (w <= 0 ||
        h <= 0 ||
        w * h > 24 * 1024 * 1024 ||
        dimension <= 0 ||
        dimension > 512) {
      throw const FormatException('Image pixel limit');
    }
    final factor = math.min(1.0, dimension / math.max(w, h));
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (w * factor).round()),
      targetHeight: math.max(1, (h * factor).round()),
    );
    image = (await codec.getNextFrame()).image;
    final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
    if (encoded == null) {
      throw const FormatException('Thumbnail encoding failed');
    }
    return encoded.buffer.asUint8List();
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
