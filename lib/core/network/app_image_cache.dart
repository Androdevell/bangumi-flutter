import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'android_image_file_service.dart';
import 'safe_image_file_service.dart';
import 'quota_cache_manager.dart';
import 'platform_http_client.dart';
import 'windows_direct_client.dart';
import '../cache/managed_image_file_system.dart';
import '../cache/cache_storage.dart';

abstract final class AppImageCache {
  static BaseCacheManager? _manager;
  static bool _initialized = false;
  static SafeImageFileService? _fileService;
  static ManagedImageFileSystem? _fileSystem;
  static const _cacheKey = 'bangumiImageCacheV2';

  static BaseCacheManager get manager => _manager ??= DefaultCacheManager();

  @visibleForTesting
  static set testManager(BaseCacheManager value) => _manager = value;

  static void initialize(
    http.Client client, {
    String cacheKey = _cacheKey,
    ManagedImageFileSystem? fileSystem,
  }) {
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
    _fileSystem =
        fileSystem ?? (cacheKey == _cacheKey ? ManagedImageFileSystem() : null);
    _manager = QuotaCacheManager(
      Config(
        cacheKey,
        fileSystem: _fileSystem ?? IOFileSystem(cacheKey),
        stalePeriod: const Duration(days: 14),
        maxNrOfCacheObjects: 600,
        fileService: service,
      ),
    );
  }

  static Future<int> diskUsageBytes() async {
    var bytes = 0;
    for (final directory in [
      await CacheStorage.images(),
      await CacheStorage.legacyImages(),
    ]) {
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File) bytes += await entity.length();
      }
    }
    return bytes;
  }

  static Future<void> clear() async {
    await clearDisk(() async {});
    clearMemory();
  }

  static Future<void> retry(String url) async {
    _fileService?.clearFailure(url);
    await manager.removeFile(url);
  }

  static int get memoryBytes =>
      PaintingBinding.instance.imageCache.currentSizeBytes;
  static int get memoryCount => PaintingBinding.instance.imageCache.currentSize;
  static void clearMemory() => PaintingBinding.instance.imageCache.clear();
  static Future<void> clearDisk(Future<void> Function() removeOrphans) async {
    Future<void> clear() async {
      Future<void> remove() async {
        await manager.emptyCache();
        _fileService?.clearFailures();
        await removeOrphans();
      }

      if (_fileSystem case final fs?) {
        await fs.withoutMigration(remove);
      } else {
        await remove();
      }
    }

    if (manager case final QuotaCacheManager quota) {
      await quota.maintain(clear);
    } else {
      await clear();
    }
  }

  static Future<void> dispose() async {
    if (!_initialized) return;
    _initialized = false;
    _fileService = null;
    await manager.dispose();
    _manager = null;
    _fileSystem = null;
  }
}
