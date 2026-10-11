import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'android_image_file_service.dart';

abstract final class AppImageCache {
  static BaseCacheManager _manager = DefaultCacheManager();
  static bool _initialized = false;
  static const _cacheKey = 'bangumiImageCacheV2';

  static BaseCacheManager get manager => _manager;

  static void initialize(http.Client client) {
    if (_initialized) return;
    _initialized = true;
    PaintingBinding.instance.imageCache
      ..maximumSize = 300
      ..maximumSizeBytes = 64 << 20;
    final FileService service =
        Platform.isAndroid
            ? AndroidImageFileService()
            : HttpFileService(httpClient: client);
    service.concurrentFetches = 3;
    _manager = CacheManager(
      Config(
        _cacheKey,
        stalePeriod: const Duration(days: 14),
        maxNrOfCacheObjects: 600,
        fileService: service,
      ),
    );
  }

  static Future<int> diskUsageBytes() async {
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}$_cacheKey',
    );
    if (!await directory.exists()) return 0;
    var bytes = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File) bytes += await entity.length();
    }
    return bytes;
  }

  static Future<void> clear() async {
    await _manager.emptyCache();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  static Future<void> dispose() async {
    if (!_initialized) return;
    _initialized = false;
    await _manager.dispose();
    _manager = DefaultCacheManager();
  }
}
