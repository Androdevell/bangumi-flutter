import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

abstract final class AppImageCache {
  static BaseCacheManager _manager = DefaultCacheManager();

  static BaseCacheManager get manager => _manager;

  static void initialize(http.Client client) {
    PaintingBinding.instance.imageCache
      ..maximumSize = 1600
      ..maximumSizeBytes = 192 << 20;
    _manager = CacheManager(
      Config(
        'bangumiImageCacheV2',
        stalePeriod: const Duration(days: 30),
        maxNrOfCacheObjects: 2400,
        fileService: HttpFileService(httpClient: client),
      ),
    );
  }

  static Future<void> clear() async {
    await _manager.emptyCache();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }
}
