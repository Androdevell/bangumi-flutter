import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/cache_usage.dart';
import '../auth/secure_vault.dart';
import '../network/app_image_cache.dart';
import '../network/quota_cache_manager.dart';
import '../update/update_download_service.dart';
import 'cache_storage.dart';
import 'public_calendar_vault.dart';
import 'calendar_snapshot.dart';
import '../diagnostics/image_diagnostics.dart';
import '../text/bbcode_document.dart';

/// 只管理明确归属本应用的可重建缓存，不扫描安全存储或用户导出目录。
class AppCacheService implements CacheMaintenance {
  AppCacheService({
    this.responses,
    Future<Directory> Function()? temporary,
    Future<Directory> Function()? support,
    Future<Directory> Function()? legacyPublic,
    Directory? globalTemporary,
    PublicCalendarVault? publicVault,
  }) : _temporary = temporary ?? getTemporaryDirectory,
       _support = support ?? getApplicationSupportDirectory,
       _legacyPublic = legacyPublic ?? getApplicationCacheDirectory,
       _globalTemporary = globalTemporary ?? Directory.systemTemp,
       _publicVault = publicVault;
  final ResponseCacheMaintenance? responses;
  final Future<Directory> Function() _temporary, _support, _legacyPublic;
  final Directory _globalTemporary;
  final PublicCalendarVault? _publicVault;
  bool _clearing = false;
  late final _temporaryRoot = _temporary();
  late final _supportRoot = _support();
  late final _legacyPublicRoot = _legacyPublic();

  Future<List<({File file, bool protected})>> _files(
    CacheCategory category,
  ) async {
    final temp = await _temporaryRoot;
    final root = '${temp.path}/${CacheStorage.namespace}';
    final directories = switch (category) {
      CacheCategory.images => [
        Directory('$root/images'),
        Directory('${temp.path}/bangumiImageCacheV2'),
      ],
      CacheCategory.publicData => [
        Directory('$root/public'),
        await _legacyPublicRoot,
      ],
      CacheCategory.temporary => [
        Directory('$root/transfers'),
        Directory('${temp.path}/bangumi_image_transfer'),
        Directory('${_globalTemporary.path}/bangumi-image-transfers-v1'),
      ],
      CacheCategory.updates => [
        Directory('${(await _supportRoot).path}/updates'),
        Directory('${temp.path}/updates'),
      ],
      CacheCategory.diagnostics => [
        Directory('${(await _supportRoot).path}/diagnostics'),
      ],
      CacheCategory.memory => <Directory>[],
    };
    final files = <({File file, bool protected})>[];
    final seen = <String>{};
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    for (final directory in directories) {
      if (directory.path.startsWith('$root/') &&
          await FileSystemEntity.type(root, followLinks: false) !=
              FileSystemEntityType.directory) {
        continue;
      }
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      await for (final entity in directory.list(
        recursive: category == CacheCategory.temporary,
        followLinks: false,
      )) {
        if (entity is! File ||
            await FileSystemEntity.type(entity.path, followLinks: false) !=
                FileSystemEntityType.file ||
            !seen.add(entity.absolute.path)) {
          continue;
        }
        final name = entity.uri.pathSegments.last;
        final owned = switch (category) {
          CacheCategory.publicData => name == 'public-calendar-v1.json',
          CacheCategory.temporary =>
            name.endsWith('.part') || name.endsWith('.migrate'),
          CacheCategory.updates => RegExp(
            r'^\d+-bangumi-[0-9.]+-(arm64-v8a\.apk|windows-x64\.zip)(\.part)?$',
          ).hasMatch(name),
          CacheCategory.diagnostics =>
            name == 'images.jsonl' || name == 'images.jsonl.previous',
          CacheCategory.images => !name.endsWith('.lock'),
          _ => false,
        };
        if (!owned) continue;
        final protected =
            (category == CacheCategory.temporary ||
                name.endsWith('.part') ||
                name.endsWith('.migrate')) &&
            !(await entity.lastModified()).isBefore(cutoff);
        files.add((file: entity, protected: protected));
      }
    }
    return files;
  }

  @override
  Future<List<ComposeCacheUsage>> scan() async {
    final results = <ComposeCacheUsage>[];
    for (final category in CacheCategory.values) {
      try {
        if (category == CacheCategory.memory) {
          results.add(
            ComposeCacheUsage(
              category,
              bytes:
                  AppImageCache.memoryBytes +
                  (responses?.cachedResponseBytes ?? 0),
              files: AppImageCache.memoryCount,
            ),
          );
          continue;
        }
        var bytes = 0, count = 0, protected = 0;
        for (final item in await _files(category)) {
          try {
            bytes += await item.file.length();
            count++;
            if (item.protected) protected++;
          } on FileSystemException {
            /* 并发完成的文件由下一次扫描更新。 */
          }
        }
        results.add(
          ComposeCacheUsage(
            category,
            bytes: bytes,
            files: count,
            protectedFiles: protected,
          ),
        );
      } catch (_) {
        results.add(ComposeCacheUsage(category, unavailable: true));
      }
    }
    return results;
  }

  @override
  Future<ComposeCacheClearResult> clear(Set<CacheCategory> categories) async {
    if (_clearing) {
      return ComposeCacheClearResult(busy: Set.unmodifiable(categories));
    }
    _clearing = true;
    final failed = <CacheCategory>{}, busy = <CacheCategory>{};
    try {
      for (final category in categories) {
        try {
          if (category == CacheCategory.memory) {
            AppImageCache.clearMemory();
            BangumiBbCode.clearCache();
            responses?.clearResponseCache();
            continue;
          }
          if (category == CacheCategory.publicData) {
            responses?.clearResponseCache();
            final vault =
                _publicVault ?? PublicCalendarVault(PlatformSecureVault());
            await vault.delete(CalendarSnapshotStore.key);
            continue;
          }
          if (category == CacheCategory.updates &&
              UpdateDownloadService.hasActiveDownloads) {
            busy.add(category);
            continue;
          }
          if (category == CacheCategory.diagnostics) {
            await ImageDiagnostics.instance.clearStored();
          }
          Future<void> remove() async {
            for (final item in await _files(category)) {
              if (category == CacheCategory.diagnostics &&
                  ImageDiagnostics.instance.owns(item.file)) {
                continue;
              }
              if (item.protected) {
                busy.add(category);
                continue;
              }
              try {
                if (await item.file.exists()) await item.file.delete();
              } on FileSystemException {
                failed.add(category);
              }
            }
          }

          if (category == CacheCategory.images) {
            final manager = AppImageCache.manager;
            if (manager is QuotaCacheManager && manager.hasActiveRequests) {
              busy.add(category);
              continue;
            }
            await AppImageCache.clearDisk(remove);
          } else if (category == CacheCategory.updates) {
            await UpdateDownloadService.maintain(remove);
          } else {
            await remove();
          }
        } on StateError catch (error) {
          if (error.message == 'cacheBusy') {
            busy.add(category);
          } else {
            failed.add(category);
          }
        } catch (_) {
          failed.add(category);
        }
      }
    } finally {
      _clearing = false;
    }
    return ComposeCacheClearResult(
      failed: Set.unmodifiable(failed),
      busy: Set.unmodifiable(busy),
    );
  }
}
