import 'dart:async';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 只经缓存管理器删除已完成且近期未使用的条目，不触碰下载中或刚返回的文件。
class QuotaCacheManager extends CacheManager with ImageCacheManager {
  QuotaCacheManager(this.configuration, {this.maxBytes = 512 * 1024 * 1024})
    : super(configuration);
  final Config configuration;
  final int maxBytes;
  final _active = <String, int>{};
  final _recent = <String, DateTime>{};
  Timer? _timer;
  Future<void>? _trimming;
  bool _closed = false;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    final id = key ?? url;
    _active[id] = (_active[id] ?? 0) + 1;
    try {
      yield* super.getFileStream(
        url,
        key: key,
        headers: headers,
        withProgress: withProgress,
      );
    } finally {
      if ((_active[id] ?? 0) <= 1) {
        _active.remove(id);
      } else {
        _active[id] = _active[id]! - 1;
      }
      _recent[id] = DateTime.now();
      if (!_closed && _timer == null) {
        _timer = Timer(const Duration(seconds: 5), () {
          _timer = null;
          _trimming ??= _trim()
              .catchError((Object _) {})
              .whenComplete(() => _trimming = null);
        });
      }
    }
  }

  Future<void> _trim() async {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    _recent.removeWhere((_, at) => at.isBefore(cutoff));
    await configuration.repo.open();
    try {
      await _trimOpened();
    } finally {
      // open 增加仓库连接计数，必须配对；CacheManager 自身的连接继续有效。
      await configuration.repo.close();
    }
  }

  Future<void> _trimOpened() async {
    final objects = await configuration.repo.getAllObjects();
    var bytes = 0;
    final sizes = <String, int>{};
    for (final entry in objects) {
      final file = await configuration.fileSystem.createFile(
        entry.relativePath,
      );
      final size =
          entry.length ?? (await file.exists() ? await file.length() : 0);
      sizes[entry.key] = size;
      bytes += size;
    }
    objects.sort(
      (a, b) =>
          (a.touched ?? DateTime(1970)).compareTo(b.touched ?? DateTime(1970)),
    );
    for (final entry in objects) {
      if (_closed || bytes <= maxBytes) break;
      if (_active.containsKey(entry.key) || _recent.containsKey(entry.key)) {
        continue;
      }
      await removeFile(entry.key);
      bytes -= sizes[entry.key] ?? 0;
    }
    // 近期文件暂时保护，但不必等下次访问才再次收敛。
    if (!_closed && bytes > maxBytes && _timer == null) {
      _timer = Timer(const Duration(minutes: 5), () {
        _timer = null;
        _trimming = _trim()
            .catchError((Object _) {})
            .whenComplete(() => _trimming = null);
      });
    }
  }

  @override
  Future<void> dispose() async {
    _closed = true;
    _timer?.cancel();
    await _trimming;
    await super.dispose();
  }
}
