import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../auth/secure_vault.dart';
import '../storage/atomic_file_store.dart';
import 'calendar_snapshot.dart';

/// 仅公开日历使用普通缓存；旧加密快照只读兼容，账号和 Cookie 不经过此存储。
class PublicCalendarVault implements SecureVault {
  PublicCalendarVault(this.legacy, {Future<Directory> Function()? directory})
    : directory = directory ?? getApplicationCacheDirectory;
  final SecureVault legacy;
  final Future<Directory> Function() directory;
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
    try {
      final file = await _file();
      if (await file.exists() && await file.length() <= 512 * 1024) {
        return await file.readAsString();
      }
    } on FileSystemException {
      /* 缓存不可用时兼容旧快照，网络仍可并行读取。 */
    }
    return legacy.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    _check(key);
    if (value.length > 512 * 1024) return;
    await files.write(await _file(), value);
  }

  @override
  Future<void> delete(String key) async {
    _check(key);
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
