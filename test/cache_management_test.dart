import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:bangumi_flutter/core/update/update_download_service.dart';
import 'package:bangumi_flutter/core/update/app_update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/cache/app_cache_service.dart';
import 'package:bangumi_flutter/core/cache/cache_storage.dart';
import 'package:bangumi_flutter/core/cache/managed_image_file_system.dart';
import 'package:bangumi_flutter/core/cache/public_calendar_vault.dart';
import 'package:bangumi_flutter/core/cache/calendar_snapshot.dart';
import 'package:bangumi_flutter/core/network/app_image_cache.dart';
import 'package:bangumi_flutter/core/network/quota_cache_manager.dart';
import 'package:bangumi_flutter/core/localization/app_localizations.dart';
import 'package:bangumi_flutter/domain/models/cache_usage.dart';
import 'package:bangumi_flutter/features/profile/cache/cache_controller.dart';
import 'package:bangumi_flutter/features/profile/cache/cache_management_page.dart';

class _ImageCache extends Fake implements BaseCacheManager {
  int cleared = 0;
  @override
  Future<void> emptyCache() async {
    cleared++;
  }
}

class _Cache implements CacheMaintenance {
  final calls = <Set<CacheCategory>>[];
  Completer<ComposeCacheClearResult>? pending;
  @override
  Future<List<ComposeCacheUsage>> scan() async => [
    for (final category in CacheCategory.values)
      ComposeCacheUsage(category, bytes: 1024, files: 1),
  ];
  @override
  Future<ComposeCacheClearResult> clear(Set<CacheCategory> categories) async {
    calls.add(Set.of(categories));
    return pending == null
        ? const ComposeCacheClearResult()
        : await pending!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late MemorySecureVault vault;
  late PublicCalendarVault calendar;
  late AppCacheService service;
  late _ImageCache images;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  Future<File> write(String path, String contents, {bool old = false}) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
    if (old) {
      await file.setLastModified(
        DateTime.now().subtract(const Duration(days: 2)),
      );
    }
    return file;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bgm-cache-134-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    vault = MemorySecureVault();
    calendar = PublicCalendarVault(
      vault,
      directory:
          () async =>
              Directory('${root.path}/${CacheStorage.namespace}/public'),
      legacyDirectory: () async => Directory('${root.path}/legacy-public'),
    );
    service = AppCacheService(
      temporary: () async => root,
      support: () async => Directory('${root.path}/support'),
      legacyPublic: () async => Directory('${root.path}/legacy-public'),
      globalTemporary: Directory('${root.path}/global'),
      publicVault: calendar,
    );
    images = _ImageCache();
    AppImageCache.testManager = images;
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (root.parent.absolute.uri.normalizePath() !=
            Directory.systemTemp.absolute.uri.normalizePath() ||
        !root.uri.pathSegments
            .where((e) => e.isNotEmpty)
            .last
            .startsWith('bgm-cache-134-')) {
      throw StateError('Unexpected fixture path');
    }
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'storage scan separates categories and includes legacy images',
    () async {
      await write('${CacheStorage.namespace}/images/one.jpg', '123');
      await write('bangumiImageCacheV2/two.jpg', '12');
      await write(
        '${CacheStorage.namespace}/public/public-calendar-v1.json',
        '{}',
      );
      await write(
        'support/updates/12-bangumi-1.3.3-windows-x64.zip',
        'package',
      );
      await write('support/secure/credentials', 'never-clear');
      final usage = {
        for (final item in await service.scan()) item.category: item,
      };
      expect(usage[CacheCategory.images]!.bytes, 5);
      expect(usage[CacheCategory.images]!.files, 2);
      expect(usage[CacheCategory.updates]!.bytes, 7);
      expect(usage.values.any((e) => e.unavailable), false);
    },
  );
  test(
    'clear images updates index and both payload directories but preserves settings and exports',
    () async {
      final newer = await write(
        '${CacheStorage.namespace}/images/a.jpg',
        'image',
      );
      final older = await write('bangumiImageCacheV2/b.jpg', 'image');
      final credentials = await write('support/secure/session', 'token');
      final exported = await write('exported/image.png', 'user image');
      final result = await service.clear({CacheCategory.images});
      expect(result.failed, isEmpty);
      expect(images.cleared, 1);
      expect(await newer.exists(), false);
      expect(await older.exists(), false);
      expect(await credentials.readAsString(), 'token');
      expect(await exported.readAsString(), 'user image');
      expect(
        (await service.scan())
            .firstWhere((e) => e.category == CacheCategory.images)
            .bytes,
        0,
      );
    },
  );
  test('temporary cleanup retains fresh fragments and unknown files', () async {
    final old = await write(
      '${CacheStorage.namespace}/transfers/transfer-old/image.part',
      'old',
      old: true,
    );
    final fresh = await write(
      '${CacheStorage.namespace}/transfers/transfer-new/image.part',
      'fresh',
    );
    final foreign = await write(
      '${CacheStorage.namespace}/transfers/notes.txt',
      'keep',
      old: true,
    );
    final result = await service.clear({CacheCategory.temporary});
    expect(await old.exists(), false);
    expect(await fresh.exists(), true);
    expect(await foreign.exists(), true);
    expect(result.busy, contains(CacheCategory.temporary));
  });
  test(
    'updates only remove application package names, not unknown archives',
    () async {
      final package = await write(
        'support/updates/123-bangumi-1.3.3-windows-x64.zip',
        'owned',
      );
      final foreign = await write('support/updates/work.zip', 'keep');
      await service.clear({CacheCategory.updates});
      expect(await package.exists(), false);
      expect(await foreign.exists(), true);
    },
  );
  test(
    'public cache clear cannot fall back to legacy secure or plaintext snapshots',
    () async {
      await vault.write(CalendarSnapshotStore.key, 'legacy snapshot');
      await vault.write('app.preference.theme.v1', 'preserve');
      await write('legacy-public/public-calendar-v1.json', 'older plain');
      await calendar.write(CalendarSnapshotStore.key, 'current');
      await service.clear({CacheCategory.publicData});
      expect(await calendar.read(CalendarSnapshotStore.key), isNull);
      expect(await vault.read('app.preference.theme.v1'), 'preserve');
    },
  );
  test(
    'legacy plaintext public snapshot is migrated without reading other keys',
    () async {
      await write('legacy-public/public-calendar-v1.json', 'snapshot');
      expect(await calendar.read(CalendarSnapshotStore.key), 'snapshot');
      expect(
        await File(
          '${root.path}/${CacheStorage.namespace}/public/public-calendar-v1.json',
        ).readAsString(),
        'snapshot',
      );
    },
  );
  test(
    'image files migrate lazily and maintenance does not copy before deletion',
    () async {
      final old = await write('legacy-images/fixture.jpg', 'image data');
      final fs = ManagedImageFileSystem(
        key: CacheStorage.imageKey,
        legacy: () async => Directory('${root.path}/legacy-images'),
      );
      expect(await old.exists(), true);
      final file = await fs.createFile('fixture.jpg');
      expect(file.path, startsWith(root.path));
      expect(await file.readAsString(), 'image data');
      expect(await old.exists(), false);
      await write('legacy-images/unused.jpg', 'unused');
      await fs.withoutMigration(() async {
        expect(await (await fs.createFile('unused.jpg')).exists(), false);
      });
      await expectLater(fs.createFile('../secret'), throwsArgumentError);
    },
  );
  test(
    'active image fetch prevents maintenance; new fetch waits for maintenance',
    () async {
      final response = Completer<http.Response>();
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return response.future;
      });
      final manager = QuotaCacheManager(
        Config(
          'quota-134',
          fileSystem: IOFileSystem('quota-134'),
          repo: JsonCacheInfoRepository(path: '${root.path}/index.json'),
          fileService: HttpFileService(httpClient: client),
        ),
      );
      final pending = manager.getSingleFile('https://example.org/image');
      expect(manager.hasActiveRequests, true);
      await expectLater(manager.maintain(() async {}), throwsStateError);
      response.complete(http.Response('fixture', 200));
      await pending;
      final gate = Completer<void>();
      final maintenance = manager.maintain(() => gate.future);
      await Future<void>.delayed(Duration.zero);
      final next = manager.getSingleFile('https://example.org/next');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(requests, 1);
      gate.complete();
      await maintenance;
      await next;
      expect(requests, 2);
      await manager.dispose();
      client.close();
    },
  );
  test(
    'controller ignores duplicate clear and refreshes after partial failure',
    () async {
      final backend = _Cache()..pending = Completer();
      final controller = CacheController(backend);
      await controller.dispatch(const LoadCacheUsage());
      final first = controller.clear({CacheCategory.images});
      await controller.clear({CacheCategory.updates});
      expect(backend.calls.length, 1);
      backend.pending!.complete(
        const ComposeCacheClearResult(busy: {CacheCategory.images}),
      );
      await first;
      expect(controller.state.result!.busy, contains(CacheCategory.images));
      expect(controller.state.clearing, false);
      controller.dispose();
    },
  );
  test(
    'updates being downloaded are retained and can be cleared when complete',
    () async {
      final pending = Completer<http.Response>();
      final bytes = utf8.encode('package fixture');
      final downloader = UpdateDownloadService(
        clientFactory: () => MockClient((_) => pending.future),
        directoryProvider: () async => Directory('${root.path}/support'),
      );
      final download = downloader.download(
        ComposeUpdateAsset(
          name: 'bangumi-1.3.4-windows-x64.zip',
          url: Uri.parse(
            'https://github.com/Androdevell/bangumi-flutter/releases/download/v1.3.4/bangumi-1.3.4-windows-x64.zip',
          ),
          size: bytes.length,
          digest: 'sha256:${sha256.convert(bytes)}',
        ),
      );
      expect(UpdateDownloadService.hasActiveDownloads, true);
      final skipped = await service.clear({CacheCategory.updates});
      expect(skipped.busy, contains(CacheCategory.updates));
      pending.complete(http.Response.bytes(bytes, 200));
      await download;
      expect(downloader.error, isNull);
      final file = downloader.file!;
      expect(await file.exists(), true);
      await service.clear({CacheCategory.updates});
      expect(await file.exists(), false);
      downloader.dispose();
    },
  );
  test('clear wins over a snapshot write already awaiting storage', () async {
    final write = calendar.write(
      CalendarSnapshotStore.key,
      'old network result',
    );
    final clear = calendar.delete(CalendarSnapshotStore.key);
    await Future.wait([write, clear]);
    expect(await calendar.read(CalendarSnapshotStore.key), isNull);
  });
  test(
    'an unavailable diagnostic directory does not hide image statistics',
    () async {
      await write('${CacheStorage.namespace}/images/fixture.jpg', '123');
      final partial = AppCacheService(
        temporary: () async => root,
        support: () async => throw const FileSystemException('fixture denied'),
        legacyPublic: () async => Directory('${root.path}/legacy-public'),
        globalTemporary: Directory('${root.path}/global'),
      );
      final result = {
        for (final item in await partial.scan()) item.category: item,
      };
      expect(result[CacheCategory.images]!.bytes, 3);
      expect(result[CacheCategory.images]!.unavailable, false);
      expect(result[CacheCategory.diagnostics]!.unavailable, true);
    },
  );

  for (final locale in ['zh', 'en', 'ja']) {
    testWidgets(
      'cache page supports $locale narrow large text and confirms selected categories',
      (tester) async {
        tester.view.physicalSize = const Size(390, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = _Cache();
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(1.7)),
                  child: child!,
                ),
            home: CacheManagementPage(service: backend),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('cache-clear-selected')));
        await tester.pumpAndSettle();
        expect(backend.calls, isEmpty);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pumpAndSettle();
        expect(backend.calls.single, {
          CacheCategory.images,
          CacheCategory.publicData,
          CacheCategory.memory,
          CacheCategory.temporary,
        });
        expect(tester.takeException(), isNull);
      },
    );
  }
}
