import 'dart:typed_data';

/// 图片头部信息；只描述尺寸与格式，不持有任何原生资源。
class ImageHeader {
  const ImageHeader(this.width, this.height, this.format);

  final int width;
  final int height;

  /// 识别出的容器格式，用于日志与断言（`png` / `jpeg` / `gif` / `webp` / `bmp`）。
  final String format;

  int get pixels => width * height;

  @override
  String toString() => 'ImageHeader($format ${width}x$height)';
}

/// 判断字节流是否以已知图片格式的魔数开头。
///
/// 与 [parseImageHeader] 分开，用于区分「明显不是图片」与
/// 「是图片但本次读取窗口内取不到尺寸」（例如超长 EXIF 的 JPEG）。
bool hasImageMagic(Uint8List bytes) {
  if (bytes.length < 2) return false;
  if (_isPng(bytes)) {
    return true;
  }
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
  if (_ascii(bytes, 0, 'GIF87a') || _ascii(bytes, 0, 'GIF89a')) return true;
  if (bytes.length >= 12 &&
      _ascii(bytes, 0, 'RIFF') &&
      _ascii(bytes, 8, 'WEBP')) {
    return true;
  }
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) return true;
  return false;
}

/// 从字节流头部解析宽高；无法识别时返回 `null`。
///
/// 只解析元数据；结果不代表文件像素内容已经通过完整解码验证。
ImageHeader? parseImageHeader(Uint8List bytes) {
  if (bytes.length < 12) return null;
  if (_isPng(bytes)) return _png(bytes);
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return _jpeg(bytes);
  if (_ascii(bytes, 0, 'GIF87a') || _ascii(bytes, 0, 'GIF89a')) {
    return _gif(bytes);
  }
  if (_ascii(bytes, 0, 'RIFF') && _ascii(bytes, 8, 'WEBP')) return _webp(bytes);
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) return _bmp(bytes);
  return null;
}

ImageHeader? _png(Uint8List b) {
  if (b.length < 33 || _u32be(b, 8) != 13 || !_ascii(b, 12, 'IHDR')) {
    return null;
  }
  final width = _u32be(b, 16);
  final height = _u32be(b, 20);
  if (width <= 0 || height <= 0) return null;
  return ImageHeader(width, height, 'png');
}

ImageHeader? _jpeg(Uint8List b) {
  var i = 2;
  while (i + 9 <= b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    var marker = b[i + 1];
    // 标记前允许出现填充的 0xFF。
    while (marker == 0xFF && i + 2 < b.length) {
      i++;
      marker = b[i + 1];
    }
    if (i + 4 > b.length) return null;
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    // 进入扫描数据或文件结束仍未见到 SOF：无法确定尺寸。
    if (marker == 0xDA || marker == 0xD9) return null;
    final length = _u16be(b, i + 2);
    if (length < 2 || i + 2 + length > b.length) return null;
    final isStartOfFrame =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isStartOfFrame) {
      // SOFn: FF Cn, 长度(2), 精度(1), 高度(2), 宽度(2)
      if (length < 8 || i + 9 > b.length) return null;
      final height = _u16be(b, i + 5);
      final width = _u16be(b, i + 7);
      if (width <= 0 || height <= 0) return null;
      return ImageHeader(width, height, 'jpeg');
    }
    i += 2 + length;
  }
  return null;
}

ImageHeader? _gif(Uint8List b) {
  if (b.length < 10) return null;
  final width = _u16le(b, 6);
  final height = _u16le(b, 8);
  if (width <= 0 || height <= 0) return null;
  return ImageHeader(width, height, 'gif');
}

ImageHeader? _webp(Uint8List b) {
  if (b.length < 25) return null;
  final chunk = String.fromCharCodes(b.sublist(12, 16));
  if (chunk == 'VP8X') {
    if (b.length < 30) return null;
    final width = _u24le(b, 24) + 1;
    final height = _u24le(b, 27) + 1;
    return ImageHeader(width, height, 'webp');
  }
  if (chunk == 'VP8 ') {
    if (b.length < 30) return null;
    if (b[23] != 0x9D || b[24] != 0x01 || b[25] != 0x2A) return null;
    final width = _u16le(b, 26) & 0x3FFF;
    final height = _u16le(b, 28) & 0x3FFF;
    if (width <= 0 || height <= 0) return null;
    return ImageHeader(width, height, 'webp');
  }
  if (chunk == 'VP8L') {
    if (b.length < 25 || b[20] != 0x2F) return null;
    final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
    final width = (bits & 0x3FFF) + 1;
    final height = ((bits >> 14) & 0x3FFF) + 1;
    return ImageHeader(width, height, 'webp');
  }
  return null;
}

ImageHeader? _bmp(Uint8List b) {
  if (b.length < 26) return null;
  if (_u32le(b, 14) == 12) {
    final width = _u16le(b, 18);
    final height = _u16le(b, 20);
    return width > 0 && height > 0 ? ImageHeader(width, height, 'bmp') : null;
  }
  if (_u32le(b, 14) < 40) return null;
  final data = ByteData.sublistView(b);
  final width = data.getInt32(18, Endian.little);
  final height = data.getInt32(22, Endian.little).abs();
  if (width <= 0 || height <= 0) return null;
  return ImageHeader(width, height, 'bmp');
}

bool _isPng(Uint8List b) =>
    b.length >= 8 && b[0] == 0x89 && _ascii(b, 1, 'PNG\r\n\x1a\n');

bool _ascii(Uint8List b, int at, String value) {
  if (b.length < at + value.length) return false;
  for (var i = 0; i < value.length; i++) {
    if (b[at + i] != value.codeUnitAt(i)) return false;
  }
  return true;
}

int _u16be(Uint8List b, int at) => (b[at] << 8) | b[at + 1];

int _u16le(Uint8List b, int at) => b[at] | (b[at + 1] << 8);

int _u24le(Uint8List b, int at) => b[at] | (b[at + 1] << 8) | (b[at + 2] << 16);

int _u32be(Uint8List b, int at) =>
    (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

int _u32le(Uint8List b, int at) =>
    b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);
