import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/app/state/session_scope.dart';
import 'package:bangumi_flutter/core/media/image_save_service.dart';
import 'package:bangumi_flutter/data/repositories/remote_notification_repository.dart';
import 'package:bangumi_flutter/domain/models/notification.dart';
import 'package:bangumi_flutter/domain/repositories/notification_repository.dart';
import 'package:bangumi_flutter/features/notifications/notification_controller.dart';
import 'package:bangumi_flutter/features/notifications/notification_page.dart';
import 'package:bangumi_flutter/widgets/image_viewer_page.dart';
import 'comment_experience_test.dart' show host, editorHost, model, edit;
import 'community_extensions_test.dart' show authenticated;

const first = SessionScope(username: 'first', accountId: 1, epoch: 1);
const second = SessionScope(username: 'second', accountId: 2, epoch: 2);
ComposeNotice notice(int id, {int type = 10, bool unread = true}) =>
    ComposeNotice(
      id: id,
      type: type,
      title: 'Episode title',
      username: 'sender',
      nickname: 'Sender',
      mainId: 42,
      relatedId: 99,
      unread: unread,
    );

class Notices extends ChangeNotifier implements NotificationRepository {
  SessionScope current = first;
  List<ComposeNotice> items = [notice(1), notice(2, unread: false)];
  Future<ComposeNoticeBatch> Function(bool)? read;
  Future<void> Function(Set<int>)? write;
  final writes = <Set<int>>[];
  @override
  SessionScope get scope => current;
  @override
  Listenable get sessionChanges => this;
  void switchAccount() {
    current = second;
    notifyListeners();
  }

  @override
  Future<ComposeNoticeBatch> load({required bool unreadOnly}) async =>
      read != null
          ? read!(unreadOnly)
          : ComposeNoticeBatch(
            items.where((item) => !unreadOnly || item.unread).toList(),
            items.where((item) => !unreadOnly || item.unread).length,
          );
  @override
  Future<void> markRead(
    Set<int> ids, {
    required SessionScope expectedScope,
  }) async {
    expect(scope, expectedScope);
    writes.add(ids);
    await write?.call(ids);
    items =
        items
            .map((item) => ids.contains(item.id) ? item.read() : item)
            .toList();
  }
}

class UnavailableImageCache extends Fake implements BaseCacheManager {
  int reads = 0;
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    reads++;
    return Stream.error(const HttpException('Synthetic missing image'));
  }
}

void main() {
  test('viewer uses one aspect-preserving bounded decode provider', () {
    final cache = UnavailableImageCache();
    final provider =
        createViewerImageProvider('https://example.test/bounded.png', cache)
            as ResizeImage;
    expect(provider.width, 2048);
    expect(provider.height, 2048);
    expect(provider.policy, ResizeImagePolicy.fit);
    expect(provider.allowUpscaling, false);
  });
  testWidgets(
    'image long press opens save menu; animated zoom and fit do not refetch',
    (tester) async {
      final cache = UnavailableImageCache();
      await tester.pumpWidget(
        host(
          ImageViewerPage(
            urls: const [
              'https://example.test/viewer-gesture.png',
              'https://example.test/second.png',
            ],
            cacheManager: cache,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reads = cache.reads;
      final viewer = find.byKey(const ValueKey('viewer-transform'));
      final zoom =
          tester.widget<ValueListenableBuilder<Matrix4>>(viewer).valueListenable
              as ImageZoomController;
      const point = Offset(180, 180);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(zoom.value.getMaxScaleOnAxis(), closeTo(2.5, .01));
      expect(cache.reads, reads);
      await tester.tap(find.byIcon(Icons.fit_screen));
      await tester.pumpAndSettle();
      expect(zoom.value.getMaxScaleOnAxis(), 1);
      await tester.flingFrom(point, const Offset(-160, 0), 1600);
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
      final readsAfterSwitch = cache.reads;
      await tester.longPressAt(point);
      await tester.pumpAndSettle();
      expect(find.text('保存原图'), findsOneWidget);
      expect(cache.reads, readsAfterSwitch);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'notification read sends explicit positive IDs, never implicit clear-all',
    () async {
      final requests = <http.Request>[];
      final (api, auth) = await authenticated(
        MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(api.close);
      addTearDown(auth.dispose);
      final repo = RemoteNotificationRepository(api);
      await repo.markRead({}, expectedScope: repo.scope);
      expect(requests, isEmpty);
      await repo.markRead({3, 7}, expectedScope: repo.scope);
      expect(requests.single.url.path, '/p1/clear-notify');
      expect(jsonDecode(requests.single.body), {
        'id': [3, 7],
      });
      await expectLater(
        repo.markRead({0}, expectedScope: repo.scope),
        throwsArgumentError,
      );
      await auth.logout();
      await expectLater(
        repo.markRead({3}, expectedScope: first),
        throwsException,
      );
      expect(requests.length, 1);
    },
  );
  test(
    'notification list uses maximum 40, fresh data, and unread total',
    () async {
      final (api, auth) = await authenticated(
        MockClient((request) async {
          expect(request.url.queryParameters, {
            'limit': '40',
            'unread': 'true',
          });
          return http.Response(
            jsonEncode({
              'total': 57,
              'data': [
                {
                  'id': 5,
                  'type': 10,
                  'title': 'Title',
                  'mainID': 9,
                  'relatedID': 10,
                  'unread': true,
                  'createdAt': 1780000000,
                  'sender': {'username': 'sender'},
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      addTearDown(auth.dispose);
      final result = await RemoteNotificationRepository(
        api,
      ).load(unreadOnly: true);
      expect(result.total, 57);
      expect(result.items.single.target.toString(), 'https://bgm.tv/ep/9');
      expect(result.items.single.createdAt, isNotNull);
    },
  );
  test('late notification reads cannot populate another account', () async {
    final repo = Notices();
    final controller = NotificationController(repo);
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    final pending = Completer<ComposeNoticeBatch>();
    repo.read = (_) => pending.future;
    final task = controller.refresh();
    repo.switchAccount();
    pending.complete(ComposeNoticeBatch([notice(99)], 1));
    await task;
    expect(controller.state.items, isEmpty);
    expect(controller.state.unreadCount, 0);
    expect(controller.state.loading, false);
  });
  test(
    'read confirmation failure keeps unread marker and retries only explicit selection',
    () async {
      final repo = Notices();
      final controller = NotificationController(repo);
      addTearDown(controller.dispose);
      addTearDown(repo.dispose);
      await controller.refresh();
      repo.write = (_) async => throw const HttpException('Synthetic failure');
      expect(await controller.markRead({1, 2, 999}), false);
      expect(repo.writes.single, {1});
      expect(controller.state.items.first.unread, true);
      expect(controller.state.unreadCount, 1);
      repo.write = null;
      expect(await controller.markRead({1}), true);
      expect(controller.state.items.first.unread, false);
      expect(controller.state.unreadCount, 0);
    },
  );
  test('pre-mark poll cannot restore stale unread count', () async {
    final repo = Notices();
    final controller = NotificationController(repo);
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    await controller.refresh();
    final pending = Completer<ComposeNoticeBatch>();
    repo.read = (_) => pending.future;
    final poll = controller.poll();
    expect(await controller.markRead({1}), true);
    pending.complete(ComposeNoticeBatch([notice(1)], 1));
    await poll;
    expect(controller.state.unreadCount, 0);
    expect(controller.state.items.first.unread, false);
  });
  test(
    'unsupported notification kinds use official inbox rather than guessed target',
    () {
      expect(
        notice(1, type: 1000).target.toString(),
        'https://bgm.tv/notify/all',
      );
      expect(
        notice(1, type: 23).target.toString(),
        'https://bgm.tv/group/topic/42',
      );
    },
  );
  testWidgets(
    'comment input is a bounded bottom sheet, not a full-screen editor',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = model();
      edit(controller, 'A short comment');
      await tester.pumpWidget(editorHost(controller));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final sheet = tester.getRect(
        find.byKey(const ValueKey('compact-comment-sheet')),
      );
      expect(sheet.height, lessThan(450));
      expect(sheet.top, greaterThan(350));
      expect(find.byType(Dialog), findsNothing);
      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('comment-input')),
      );
      expect(input.expands, false);
      expect(input.maxLines, 5);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'notification page fits large Japanese text and does not mark by merely displaying',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = Notices();
      final controller = NotificationController(repo);
      await tester.pumpWidget(
        host(NotificationPage(controller: controller), locale: 'ja', scale: 2),
      );
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      repo.dispose();
    },
  );
  testWidgets('image viewer is black including app bar and dark controls', (
    tester,
  ) async {
    await tester.pumpWidget(host(const ImageViewerPage(urls: [])));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.black,
    );
    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.backgroundColor, Colors.black);
    expect(bar.foregroundColor, Colors.white);
    expect(find.text('0/0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'original GIF export retains all bytes and derives real type, not URL suffix',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'bangumi-save-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final bytes = [71, 73, 70, 56, 57, 97, ...List.generate(100, (i) => i)];
      final source = await File(
        '${folder.path}/cache-file',
      ).writeAsBytes(bytes);
      var fetched = 0, exported = 0;
      final service = ImageSaveService(
        fetch: (_) async {
          fetched++;
          return source;
        },
        export: (file, name, mime) async {
          exported++;
          expect(name, endsWith('.gif'));
          expect(mime, 'image/gif');
          expect(await file.readAsBytes(), bytes);
          return true;
        },
      );
      expect(
        await service.save(
          'https://example.test/not-an-extension',
          allowed: () => true,
        ),
        true,
      );
      expect(fetched, 1);
      expect(exported, 1);
      expect(
        await service.save('https://example.test/', allowed: () => false),
        false,
      );
      expect(fetched, 1);
      expect(exported, 1);
    },
  );
  test('permission withdrawn during fetch prevents saving', () async {
    var allowed = true, exported = false;
    final service = ImageSaveService(
      fetch: (_) async {
        allowed = false;
        return File('unused');
      },
      export: (_, _, _) async {
        exported = true;
        return true;
      },
    );
    expect(
      await service.save('https://example.test/', allowed: () => allowed),
      false,
    );
    expect(exported, false);
  });
  test('HTML and unsupported image signatures cannot be exported', () {
    expect(
      () => ImageSaveService.identify(utf8.encode('<html>challenge</html>')),
      throwsFormatException,
    );
    expect(
      ImageSaveService.identify([
        82,
        73,
        70,
        70,
        0,
        0,
        0,
        0,
        87,
        69,
        66,
        80,
      ]).extension,
      'webp',
    );
    expect(
      ImageSaveService.identify([137, 80, 78, 71, 13, 10, 26, 10]).extension,
      'png',
    );
    expect(ImageSaveService.identify([255, 216, 255]).extension, 'jpg');
  });
}
