import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../auth/secure_vault.dart';
import '../storage/atomic_file_store.dart';
import 'calendar_snapshot.dart';
import 'cache_storage.dart';

/// 仅公开日历使用普通缓存；旧加密快照只读兼容，账号和 Cookie 不经过此存储。
class PublicCalendarVault implements SecureVault {
  PublicCalendarVault(
    this.legacy, {
    Future<Directory> Function()? directory,
    Future<Directory> Function()? legacyDirectory,
  }) : directory = directory ?? CacheStorage.publicData,
       legacyDirectory =
           legacyDirectory ??
           (directory == null ? getApplicationCacheDirectory : null);
  final SecureVault legacy;
  final Future<Directory> Function() directory;
  final Future<Directory> Function()? legacyDirectory;
  static int _generation = 0;
  final files = AtomicFileStore();
  Future<File> _file() async {
    final root = await directory();
    await root.create(recursive: true);
    return File('${root.path}${Platform.pathSeparator}public-calendar-v1.json');
  }

  void _check(String key) {
    if (key != CalendarSnapshotStore.key) {
      throw ArgumentError('Public calendar key only');
    }
  }

  @override
  Future<String?> read(String key) async {
    _check(key);
    final generation = _generation;
    try {
      final file = await _file();
      if (await file.exists() && await file.length() <= 512 * 1024) {
        final raw = await file.readAsString();
        return generation == _generation ? raw : null;
      }
      if (legacyDirectory != null) {
        final old = File(
          '${(await legacyDirectory!()).path}/public-calendar-v1.json',
        );
        if (await FileSystemEntity.type(old.path, followLinks: false) ==
                FileSystemEntityType.file &&
            await old.length() <= 512 * 1024) {
          final raw = await old.readAsString();
          if (generation != _generation) return null;
          await write(key, raw);
          return generation == _generation ? raw : null;
        }
      }
    } on FileSystemException {
      /* 缓存不可用时兼容旧快照，网络仍可并行读取。 */
    }
    final raw = await legacy.read(key);
    return generation == _generation ? raw : null;
  }

  @override
  Future<void> write(String key, String value) async {
    _check(key);
    if (value.length > 512 * 1024) return;
    final generation = _generation;
    try {
      await AtomicFileStore(
        beforeCommit: () async {
          if (generation != _generation) throw const _CacheWriteCancelled();
        },
      ).write(await _file(), value);
    } on _CacheWriteCancelled {
      /* 清理之后不提交旧写入。 */
    }
  }

  @override
  Future<void> delete(String key) async {
    _check(key);
    _generation++;
    final file = await _file();
    await files.locked(file, () async {
      if (await file.exists()) await file.delete();
      if (legacyDirectory != null) {
        final old = File(
          '${(await legacyDirectory!()).path}/public-calendar-v1.json',
        );
        if (old.absolute.path != file.absolute.path &&
            await FileSystemEntity.type(old.path, followLinks: false) ==
                FileSystemEntityType.file) {
          await old.delete();
        }
      }
      await legacy.delete(key);
    });
  }
}

class _CacheWriteCancelled implements Exception {
  const _CacheWriteCancelled();
}
