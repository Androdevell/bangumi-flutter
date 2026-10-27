// Windows AOT 图片失败路径回归；由 windows-image-smoke.ps1 启动。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/core/network/safe_image_file_service.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:bangumi_flutter/core/network/app_image_cache.dart';
import 'package:bangumi_flutter/core/cache/app_cache_service.dart';
import 'package:bangumi_flutter/core/cache/cache_storage.dart';
import 'package:bangumi_flutter/core/cache/public_calendar_vault.dart';
import 'package:bangumi_flutter/core/cache/calendar_snapshot.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/domain/models/cache_usage.dart';

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
    await _cacheSmoke();
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

class _SmokeCache implements BaseCacheManager {
  int cleared = 0;
  @override
  Future<void> emptyCache() async {
    cleared++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Smoke-only cache');
}

Future<void> _cacheSmoke() async {
  final root = await Directory.systemTemp.createTemp('bgm-cache-smoke-');
  final cache = _SmokeCache();
  AppImageCache.testManager = cache;
  Future<File> write(String path, String value) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    return file.writeAsString(value);
  }

  try {
    final vault = MemorySecureVault();
    await vault.write('fixture.settings', 'preserve');
    await vault.write(CalendarSnapshotStore.key, 'old snapshot');
    final public = PublicCalendarVault(
      vault,
      directory:
          () async =>
              Directory('${root.path}/${CacheStorage.namespace}/public'),
    );
    await public.write(CalendarSnapshotStore.key, 'current snapshot');
    await write('${CacheStorage.namespace}/images/one.jpg', 'image');
    await write('bangumiImageCacheV2/two.jpg', 'legacy');
    await write('support/updates/1-bangumi-1.3.4-windows-x64.zip', 'package');
    await write('support/diagnostics/images.jsonl', 'diagnostic fixture');
    final credentials = await write('support/secure/session', 'preserve');
    final exported = await write('exported/image.jpg', 'preserve');
    final stale = await write(
      '${CacheStorage.namespace}/transfers/transfer-old/image.part',
      'stale',
    );
    await stale.setLastModified(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    final fresh = await write(
      '${CacheStorage.namespace}/transfers/transfer-new/image.part',
      'fresh',
    );
    final service = AppCacheService(
      temporary: () async => root,
      support: () async => Directory('${root.path}/support'),
      legacyPublic: () async => Directory('${root.path}/legacy-public'),
      globalTemporary: Directory('${root.path}/global'),
      publicVault: public,
    );
    if ((await service.scan()).any((e) => e.unavailable)) {
      throw StateError('Cache scan failed');
    }
    final result = await service.clear(CacheCategory.values.toSet());
    if (result.failed.isNotEmpty ||
        !result.busy.contains(CacheCategory.temporary) ||
        cache.cleared != 1) {
      throw StateError('Cache clear result failed');
    }
    final after = await service.scan();
    if (after
        .where(
          (e) =>
              e.category != CacheCategory.temporary &&
              e.category != CacheCategory.memory,
        )
        .any((e) => e.bytes != 0)) {
      throw StateError('Cache bytes retained');
    }
    if (await stale.exists() ||
        !await fresh.exists() ||
        await credentials.readAsString() != 'preserve' ||
        await exported.readAsString() != 'preserve' ||
        await vault.read('fixture.settings') != 'preserve' ||
        await public.read(CalendarSnapshotStore.key) != null) {
      throw StateError('Cache ownership failed');
    }
    stdout.writeln('Windows cache storage smoke passed: 6 categories');
  } finally {
    if (root.parent.absolute.uri.normalizePath() !=
            Directory.systemTemp.absolute.uri.normalizePath() ||
        !root.uri.pathSegments
            .where((e) => e.isNotEmpty)
            .last
            .startsWith('bgm-cache-smoke-')) {
      throw StateError('Unexpected smoke directory');
    }
    await root.delete(recursive: true);
  }
}
