// Windows AOT 图片失败路径回归；由 windows-image-smoke.ps1 启动。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/core/network/safe_image_file_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_verify()));
}

Future<void> _verify() async {
  final deadline = Timer(const Duration(seconds: 30), () => exit(2));
  final normal = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  );
  // 只修改 IHDR 并校正 CRC，验证元数据阈值；不分配或解码 3600 万像素。
  final oversized = Uint8List.fromList(normal);
  final header = ByteData.sublistView(oversized);
  header.setUint32(16, 6000);
  header.setUint32(20, 6000);
  var crc = 0xffffffff;
  for (final value in oversized.sublist(12, 29)) {
    crc ^= value;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  header.setUint32(29, crc ^ 0xffffffff);
  var payload = normal;
  final client = MockClient(
    (_) async => http.Response.bytes(
      payload,
      200,
      headers: {'content-type': 'image/png'},
    ),
  );
  final service = SafeImageFileService(
    client,
    lookup: (_) async => [InternetAddress('8.8.8.8')],
  );
  try {
    for (var cycle = 0; cycle < 30; cycle++) {
      for (final kind in ['oversized', 'corrupt', 'normal']) {
        payload = switch (kind) {
          'oversized' => oversized,
          'corrupt' => Uint8List.fromList(utf8.encode('invalid fixture')),
          _ => normal,
        };
        Object? failure;
        try {
          final result = await service.get(
            'https://lain.bgm.tv/aot-fixture.png?cycle=$cycle&kind=$kind',
          );
          await result.content.drain<void>();
        } on Object catch (error) {
          failure = error;
        }
        if (kind == 'normal' && failure != null) {
          throw StateError('Normal image failed after rejected image');
        }
        if (kind == 'oversized' &&
            (failure is! HttpException ||
                failure.message != 'Image pixel limit exceeded')) {
          throw StateError('Oversized image was not rejected by pixel budget');
        }
        if (kind == 'corrupt' && failure == null) {
          throw StateError('Corrupt image was accepted');
        }
      }
    }
    stdout.writeln('Windows AOT image smoke passed: 90 cases');
    deadline.cancel();
    client.close();
    exit(0);
  } on Object catch (error) {
    stderr.writeln('Windows AOT image smoke failed: ${error.runtimeType}');
    deadline.cancel();
    client.close();
    exit(1);
  }
}
