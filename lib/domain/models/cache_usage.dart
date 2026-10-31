import 'package:flutter/foundation.dart';

enum CacheCategory {
  images,
  publicData,
  memory,
  temporary,
  updates,
  diagnostics,
}

@immutable
class ComposeCacheUsage {
  const ComposeCacheUsage(
    this.category, {
    this.bytes = 0,
    this.files = 0,
    this.protectedFiles = 0,
    this.protectedBytes = 0,
    this.unavailable = false,
  });
  final CacheCategory category;
  final int bytes;
  final int files;
  final int protectedFiles;
  final int protectedBytes;
  int get reclaimableBytes => (bytes - protectedBytes).clamp(0, bytes);
  final bool unavailable;
}

@immutable
class ComposeCacheClearResult {
  const ComposeCacheClearResult({this.failed = const {}, this.busy = const {}});
  final Set<CacheCategory> failed;
  final Set<CacheCategory> busy;
}

abstract interface class CacheMaintenance {
  Future<List<ComposeCacheUsage>> scan();
  Future<ComposeCacheClearResult> clear(Set<CacheCategory> categories);
}

abstract interface class ResponseCacheMaintenance {
  int get cachedResponseBytes;
  void clearResponseCache();
}
