import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'android_image_file_service.dart';
import 'safe_image_file_service.dart';
import 'quota_cache_manager.dart';
import 'platform_http_client.dart';
import 'windows_direct_client.dart';

abstract final class AppImageCache {
  static BaseCacheManager _manager = DefaultCacheManager();
  static bool _initialized = false;
  static SafeImageFileService? _fileService;
  static const _cacheKey = 'bangumiImageCacheV2';

  static BaseCacheManager get manager => _manager;

  @visibleForTesting
  static set testManager(BaseCacheManager value) => _manager = value;

  static void initialize(http.Client client, {String cacheKey = _cacheKey}) {
    if (_initialized) return;
    _initialized = true;
    PaintingBinding.instance.imageCache
      ..maximumSize = 300
      ..maximumSizeBytes = 64 << 20;
    final FileService service =
        Platform.isAndroid
            ? AndroidImageFileService()
            : SafeImageFileService(
              client,
              lookup:
                  Platform.isWindows &&
                          windowsNetworkMode == WindowsNetworkMode.direct
                      ? resolveWindowsDirectHost
                      : null,
            );
    service.concurrentFetches = 3;
    _fileService = service is SafeImageFileService ? service : null;
    _manager = QuotaCacheManager(
      Config(
        cacheKey,
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

  static Future<void> retry(String url) async {
    _fileService?.clearFailure(url);
    await _manager.removeFile(url);
  }

  static Future<void> dispose() async {
    if (!_initialized) return;
    _initialized = false;
    _fileService = null;
    await _manager.dispose();
    _manager = DefaultCacheManager();
  }
}
