import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:bangumi_flutter/core/network/image_transfer_files.dart';
import 'package:bangumi_flutter/core/network/safe_image_file_service.dart';

/// HTTP 单元测试注入独立目录；不依赖桌面插件，不访问真实应用缓存。
SafeImageFileService fixtureImageService(
  http.Client client, {
  Future<List<InternetAddress>> Function(String)? lookup,
}) {
  final root = Directory.systemTemp.createTempSync('bgm-http-fixture-');
  addTearDown(() async {
    if (root.parent.absolute.uri.normalizePath() !=
            Directory.systemTemp.absolute.uri.normalizePath() ||
        !root.uri.pathSegments
            .where((e) => e.isNotEmpty)
            .last
            .startsWith('bgm-http-fixture-')) {
      throw StateError('Unexpected test directory');
    }
    if (await root.exists()) await root.delete(recursive: true);
  });
  return SafeImageFileService(
    client,
    lookup: lookup,
    files: ImageTransferFiles(directory: root),
  );
}
