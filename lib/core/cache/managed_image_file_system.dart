import 'dart:io' as io;
import 'dart:async';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'cache_storage.dart';

/// 保留缓存索引，命中旧文件时才迁移，避免启动时复制整份图片缓存。
class ManagedImageFileSystem extends IOFileSystem {
  ManagedImageFileSystem({
    String key = CacheStorage.imageKey,
    Future<io.Directory> Function()? legacy,
  }) : _legacy = legacy ?? CacheStorage.legacyImages,
       _key = key,
       super(key);
  final String _key;
  final Future<io.Directory> Function() _legacy;
  int _maintenance = 0;
  final _pending = <String, Future<void>>{};

  Future<T> withoutMigration<T>(Future<T> Function() action) async {
    _maintenance++;
    try {
      return await action();
    } finally {
      _maintenance--;
    }
  }

  @override
  createFile(String name) async {
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains('\\') ||
        name == '..') {
      throw ArgumentError('Cache filename only');
    }
    final file = await super.createFile(name);
    if (_key == CacheStorage.imageKey &&
        await io.FileSystemEntity.type(
              (await CacheStorage.root()).path,
              followLinks: false,
            ) !=
            io.FileSystemEntityType.directory) {
      throw const io.FileSystemException(
        'Managed cache directory is not owned',
      );
    }
    if (_maintenance == 0 && !await file.exists()) {
      final pending = _pending[name] ??= _migrate(name, file.path);
      try {
        await pending;
      } finally {
        if (identical(_pending[name], pending)) {
          unawaited(_pending.remove(name));
        }
      }
    }
    return file;
  }

  Future<void> _migrate(String name, String destination) async {
    io.File? part;
    try {
      final directory = await _legacy();
      if (await io.FileSystemEntity.type(directory.path, followLinks: false) !=
          io.FileSystemEntityType.directory) {
        return;
      }
      final source = io.File('${directory.path}/$name');
      if (await io.FileSystemEntity.type(source.path, followLinks: false) !=
          io.FileSystemEntityType.file) {
        return;
      }
      final length = await source.length();
      if (length > 20 * 1024 * 1024) return;
      final target = io.File(destination);
      part = io.File(
        '$destination.${DateTime.now().microsecondsSinceEpoch}.migrate',
      );
      await source.copy(part.path);
      if (await part.length() != length) return;
      if (!await target.exists()) await part.rename(target.path);
      if (await target.length() == length) await source.delete();
    } on io.FileSystemException {
      // 迁移失败由原有缓存过期与网络重试处理，不留下可见的半文件。
    } finally {
      if (part != null && await part.exists()) {
        try {
          await part.delete();
        } on io.FileSystemException {
          /* 下次维护回收。 */
        }
      }
    }
  }
}
