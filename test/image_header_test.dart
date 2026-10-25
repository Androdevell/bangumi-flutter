import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bangumi_flutter/core/network/image_header.dart';
import 'package:bangumi_flutter/core/network/safe_image_file_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 1×1 透明 PNG。
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
);

/// 把 PNG 的 IHDR 改成指定尺寸并修正 CRC。
Uint8List _resizePngHeader(Uint8List source, int width, int height) {
  final bytes = Uint8List.fromList(source);
  final view = ByteData.sublistView(bytes);
  view.setUint32(16, width);
  view.setUint32(20, height);
  var crc = 0xffffffff;
  for (final value in bytes.sublist(12, 29)) {
    crc ^= value;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  view.setUint32(29, crc ^ 0xffffffff);
  return bytes;
}

/// 只构造能被头部解析器识别的 JPEG（SOF0 段）。
Uint8List _jpeg(int width, int height) {
  final bytes =
      BytesBuilder()
        ..add([0xFF, 0xD8])
        ..add([0xFF, 0xC0, 0x00, 0x11, 0x08])
        ..add([height >> 8, height & 0xFF])
        ..add([width >> 8, width & 0xFF])
        ..add(List<int>.filled(16, 0));
  return bytes.takeBytes();
}

Uint8List _webpExtended(int width, int height) {
  final w = width - 1;
  final h = height - 1;
  final bytes =
      BytesBuilder()
        ..add(ascii.encode('RIFF'))
        ..add([0x00, 0x00, 0x00, 0x00])
        ..add(ascii.encode('WEBP'))
        ..add(ascii.encode('VP8X'))
        ..add([10, 0, 0, 0])
        ..add([0, 0, 0, 0])
        ..add([w & 0xFF, (w >> 8) & 0xFF, (w >> 16) & 0xFF])
        ..add([h & 0xFF, (h >> 8) & 0xFF, (h >> 16) & 0xFF])
        ..add(List<int>.filled(8, 0));
  return bytes.takeBytes();
}

Uint8List _gif(int width, int height) {
  final bytes =
      BytesBuilder()
        ..add(ascii.encode('GIF89a'))
        ..add([width & 0xFF, width >> 8])
        ..add([height & 0xFF, height >> 8])
        ..add(List<int>.filled(16, 0));
  return bytes.takeBytes();
}

SafeImageFileService _service({
  required Uint8List body,
  String type = 'image/png',
}) => SafeImageFileService(
  MockClient(
    (_) async =>
        http.Response.bytes(body, 200, headers: {'content-type': type}),
  ),
  lookup: (_) async => [InternetAddress('93.184.216.34')],
);

void main() {
  group('图片头解析', () {
    test('PNG', () {
      final header = parseImageHeader(_png);
      expect(header, isNotNull);
      expect(header!.format, 'png');
      expect(header.width, 1);
      expect(header.height, 1);
    });

    test('JPEG（SOF0）', () {
      final header = parseImageHeader(_jpeg(32, 16));
      expect(header!.format, 'jpeg');
      expect(header.width, 32);
      expect(header.height, 16);
    });

    test('WebP（VP8X）', () {
      final header = parseImageHeader(_webpExtended(800, 600));
      expect(header!.format, 'webp');
      expect(header.width, 800);
      expect(header.height, 600);
    });

    test('GIF', () {
      final header = parseImageHeader(_gif(4, 3));
      expect(header!.format, 'gif');
      expect(header.width, 4);
      expect(header.height, 3);
    });

    test('非图片数据既没有魔数也解析不出尺寸', () {
      final html = Uint8List.fromList(utf8.encode('<html>404</html>'));
      expect(parseImageHeader(html), isNull);
      expect(hasImageMagic(html), isFalse);
    });
  });

  group('图片尺寸校验', () {
    test('正常小图放行', () async {
      final response = await _service(
        body: _png,
      ).get('https://lain.bgm.tv/ok.png');
      expect(await response.content.expand((c) => c).toList(), _png);
    });

    test('超过像素预算被拒绝', () async {
      final oversized = _resizePngHeader(_png, 6000, 6000);
      await expectLater(
        _service(body: oversized).get('https://lain.bgm.tv/big.png'),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            'Image pixel limit exceeded',
          ),
        ),
      );
    });

    test('4K 剧照仍在预算内', () async {
      final still = _resizePngHeader(_png, 3840, 2160);
      final response = await _service(
        body: still,
      ).get('https://lain.bgm.tv/still.png');
      expect(await response.content.expand((c) => c).toList(), still);
    });

    test('伪装成 octet-stream 的 HTML 被拒绝（旧实现会送进原生解码器）', () async {
      final html = Uint8List.fromList(
        utf8.encode('<html><body>502 Bad Gateway</body></html>'),
      );
      await expectLater(
        _service(
          body: html,
          type: 'application/octet-stream',
        ).get('https://lain.bgm.tv/broken.png'),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            'Image format not recognized',
          ),
        ),
      );
    });

    test('过短的响应体被拒绝', () async {
      await expectLater(
        _service(
          body: Uint8List.fromList([1, 2, 3]),
        ).get('https://lain.bgm.tv/tiny.png'),
        throwsA(isA<HttpException>()),
      );
    });
  });
}
