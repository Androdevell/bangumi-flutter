import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/core/storage/atomic_file_store.dart';
import 'package:bangumi_flutter/core/auth/auth_service.dart';
import 'package:bangumi_flutter/core/auth/auth_models.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/network/bounded_response.dart';
import 'package:bangumi_flutter/core/network/cookie_session_client.dart';
import 'package:bangumi_flutter/core/network/read_task_scope.dart';
import 'package:bangumi_flutter/core/network/image_transport.dart';
import 'package:bangumi_flutter/core/network/image_transfer_files.dart';
import 'package:bangumi_flutter/core/community_models.dart';
import 'package:bangumi_flutter/core/paged.dart';
import 'package:bangumi_flutter/core/paged_controller.dart';
import 'package:bangumi_flutter/core/media/safe_image_thumbnail.dart';
import 'package:bangumi_flutter/core/update/update_download_service.dart';
import 'package:bangumi_flutter/core/update/app_update_service.dart';
import 'session_upgrade_regression_test.dart' show previousInstall;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'atomic replacement preserves previous record on interrupted commit and serializes writes',
    () async {
      final folder = await Directory.systemTemp.createTemp('bgm-atomic-test-');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/record');
      final store = AtomicFileStore();
      await store.write(file, 'old');
      await expectLater(
        AtomicFileStore(
          beforeCommit: () async => throw StateError('injected'),
        ).write(file, 'new'),
        throwsStateError,
      );
      expect(await file.readAsString(), 'old');
      await Future.wait(
        List.generate(30, (index) => store.write(file, '$index')),
      );
      expect(await file.readAsString(), '29');
      expect(
        await folder.list().where((f) => f.path.endsWith('.tmp')).length,
        0,
      );
    },
  );

  test(
    'session migration commits one complete identity and logout tombstone prevents legacy resurrection',
    () async {
      final vault = await previousInstall();
      final cookies = PersistentCookieStore(vault);
      final client = MockClient(
        (_) async => throw StateError('No network expected'),
      );
      addTearDown(client.close);
      AuthService create() =>
          AuthService(client: client, cookies: cookies, vault: vault);
      final auth = create();
      addTearDown(auth.dispose);
      await auth.initialize();
      await auth.updateProfileIdentity(
        username: 'tester',
        nickname: 'New',
        avatarUrl: '',
      );
      expect(await vault.read('bangumi.auth.token.v1'), isNull);
      final restored = create();
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.user!.nickname, 'New');
      await restored.logout();
      await vault.write(
        'bangumi.auth.user.v1',
        jsonEncode({'username': 'stale'}),
      );
      await vault.write(
        'bangumi.auth.token.v1',
        jsonEncode({'access_token': 'stale', 'refresh_token': 'stale'}),
      );
      final again = create();
      addTearDown(again.dispose);
      await again.initialize();
      expect(again.isLoggedIn, false);
    },
  );

  test(
    'oversized declared and streamed responses are cancelled without GET retries',
    () async {
      var requests = 0, cancelled = false;
      final stream = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final reading = readBoundedResponse(
        http.StreamedResponse(stream.stream, 200),
        maxBytes: 3,
      );
      final assertion = expectLater(
        reading,
        throwsA(isA<ResponseLimitException>()),
      );
      stream.add([1, 2, 3, 4]);
      await assertion;
      expect(cancelled, true);
      await stream.close();
      final api = ApiClient(
        client: MockClient((_) async {
          requests++;
          return http.Response('x' * (4 * 1024 * 1024 + 1), 200);
        }),
      );
      addTearDown(api.close);
      await expectLater(
        api.get('p1/large'),
        throwsA(isA<ResponseLimitException>()),
      );
      expect(requests, 1);
      expect(
        await decodeResponseJson(
          http.Response(jsonEncode({'value': 'x' * 70000}), 200),
        ),
        containsPair('value', 'x' * 70000),
      );
    },
  );

  test(
    'shared GET survives one consumer cancellation; abandoned GET releases its slot',
    () async {
      final pending = <String, Completer<http.Response>>{};
      final seen = <String>[];
      final api = ApiClient(
        client: MockClient((r) {
          seen.add(r.url.path);
          return (pending[r.url.path] ??= Completer()).future;
        }),
      );
      addTearDown(api.close);
      final first = ReadTaskScope(), second = ReadTaskScope();
      final a = first.run(() => api.get('p1/shared'));
      final failed = expectLater(a, throwsA(isA<ReadCancelledException>()));
      final b = second.run(() => api.get('p1/shared'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      first.cancel();
      await failed;
      pending['/p1/shared']!.complete(http.Response('{"ok":true}', 200));
      expect(await b, {'ok': true});
      expect(seen.length, 1);
      final scopes = List.generate(3, (_) => ReadTaskScope());
      final old = List.generate(
        3,
        (i) => scopes[i].run(() => api.get('p1/old$i')),
      );
      final assertions =
          old
              .map(
                (f) => expectLater(f, throwsA(isA<ReadCancelledException>())),
              )
              .toList();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      for (final scope in scopes) {
        scope.cancel();
      }
      await Future.wait(assertions);
      final fresh = api.get('p1/latest');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(seen, contains('/p1/latest'));
      pending['/p1/latest']!.complete(http.Response('{}', 200));
      await fresh;
      for (var i = 0; i < 3; i++) {
        pending['/p1/old$i']!.complete(http.Response('{}', 200));
      }
    },
  );

  test('API cache respects response-byte budget and recent access', () async {
    final requests = <String>[];
    final api = ApiClient(
      cacheMaxBytes: 30,
      client: MockClient((r) async {
        requests.add(r.url.path);
        return http.Response('{"value":123}', 200);
      }),
    );
    addTearDown(api.close);
    await api.get('p1/a');
    await api.get('p1/b');
    await api.get('p1/a');
    await api.get('p1/c');
    await api.get('p1/a');
    expect(requests.where((p) => p == '/p1/a').length, 1);
    await api.get('p1/b');
    expect(requests.where((p) => p == '/p1/b').length, 2);
  });

  test(
    'unknown image origin is denied at real connection resolver, not only preflight',
    () => HttpOverrides.runWithHttpOverrides(() async {
      var lookups = 0;
      final transport = ImageTransport(
        MockClient((_) async => throw StateError('No compatible origin')),
        lookup: (_) async {
          lookups++;
          return [InternetAddress.loopbackIPv4];
        },
      );
      addTearDown(transport.close);
      await expectLater(
        transport.get(Uri.parse('https://untrusted.example.test/image')),
        throwsA(isA<Exception>()),
      );
      expect(lookups, 1);
      expect(
        ImageTransport.compatibleHost('img9.doubanio.com.evil.test'),
        false,
      );
    }, _RealHttpOverrides()),
  );

  test(
    'reply tree has finite depth and node budget while retaining a truncation notice',
    () {
      Map<String, dynamic> root = {'id': 100, 'content': 'leaf'};
      for (var i = 0; i < 80; i++) {
        root = {
          'id': i,
          'content': 'text',
          'replies': [root],
        };
      }
      var reply = CommunityReply.fromJson(root), depth = 0;
      while (reply.replies.isNotEmpty) {
        depth++;
        reply = reply.replies.single;
      }
      expect(depth, 16);
      expect(reply.truncated, true);
      final wide = CommunityReply.fromJson({
        'id': 1,
        'replies': List.generate(3000, (i) => {'id': i + 2}),
      });
      expect(wide.replies.length, 1999);
      expect(wide.truncated, true);
    },
  );

  test(
    'paged snapshots remain immutable and stable until data changes',
    () async {
      final controller = PagedController<int>(
        load:
            (_) async => Paged(items: [1, 1, 2], offset: 0, limit: 3, total: 2),
        idOf: (i) => i,
      );
      addTearDown(controller.dispose);
      await controller.loadMore();
      expect(identical(controller.items, controller.items), true);
      expect(controller.items, [1, 2]);
      expect(() => controller.items.add(3), throwsUnsupportedError);
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 800, 400),
        ui.Paint()..color = const ui.Color(0xffe977a3),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(800, 400);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final thumbnail = await safeImageThumbnail(png!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      final buffer = await ui.ImmutableBuffer.fromUint8List(thumbnail);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      expect(descriptor.width, 256);
      expect(descriptor.height, 128);
      descriptor.dispose();
      buffer.dispose();
    },
  );

  test(
    'updates without a digest never start downloading or expose installable files',
    () async {
      var calls = 0;
      final service = UpdateDownloadService(
        clientFactory:
            () => MockClient((_) async {
              calls++;
              throw StateError('No request');
            }),
      );
      addTearDown(service.dispose);
      await service.download(
        ComposeUpdateAsset(
          name: 'bangumi-1.2.10-windows-x64.zip',
          url: Uri.parse(
            'https://github.com/Androdevell/bangumi-flutter/releases/download/v1.2.10/bangumi-1.2.10-windows-x64.zip',
          ),
          size: 10,
        ),
      );
      expect(calls, 0);
      expect(service.file, isNull);
      expect(service.error, 'downloadNoDigest');
      expect(await service.installAndroid(), false);
    },
  );

  for (final invalid in [
    'host',
    'path',
    'state',
    'missing-state',
    'duplicate-code',
  ]) {
    test('OAuth rejects $invalid before exchanging a code', () async {
      final vault = MemorySecureVault();
      final states = <String>[];
      var exchanges = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/login') {
          return http.Response(
            '<main id="main"><div id="header"><h1>Fixture</h1></div></main>'
            '<div class="idBadgerNeue"><a class="avatar" href="/user/tester"></a></div>'
            '<input name="formhash" value="fixture">',
            200,
          );
        }
        if (request.url.path == '/oauth/authorize') {
          final state = request.url.queryParameters['state']!;
          states.add(state);
          expect(state.length, greaterThanOrEqualTo(43));
          expect(request.bodyFields['state'], state);
          var uri = Uri.parse('http://localhost/callback').replace(
            queryParameters: {
              'code': 'one-time',
              if (invalid != 'missing-state')
                'state': invalid == 'state' ? 'wrong' : state,
            },
          );
          if (invalid == 'host') uri = uri.replace(host: 'evil.test');
          if (invalid == 'path') uri = uri.replace(path: '/unexpected');
          if (invalid == 'duplicate-code') {
            uri = uri.replace(query: '${uri.query}&code=second');
          }
          return http.Response('', 302, headers: {'location': '$uri'});
        }
        exchanges++;
        return http.Response('{}', 400);
      });
      addTearDown(client.close);
      final auth = AuthService(
        client: client,
        cookies: PersistentCookieStore(vault),
        vault: vault,
        appId: 'fixture-id',
        appSecret: 'fixture-secret',
      );
      addTearDown(auth.dispose);
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(auth.beginLogin(), throwsA(isA<AuthException>()));
      }
      expect(exchanges, 0);
      expect(states.toSet().length, 2);
      expect(auth.isLoggedIn, false);
    });
  }

  test(
    'update cleanup preserves current, one previous, recent parts and foreign files',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'bgm-update-prune-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final old = DateTime.now().subtract(const Duration(days: 2));
      Future<File> create(String name, {bool stale = false}) async {
        final file = await File(
          '${folder.path}/$name',
        ).writeAsString('fixture');
        if (stale) await file.setLastModified(old);
        return file;
      }

      final current = await create('300-bangumi-1.2.10-arm64-v8a.apk');
      final previous = await create('200-bangumi-1.2.9-arm64-v8a.apk');
      final older = await create(
        '100-bangumi-1.2.8-arm64-v8a.apk',
        stale: true,
      );
      final stalePart = await create(
        '90-bangumi-1.2.7-arm64-v8a.apk.part',
        stale: true,
      );
      final active = await create('400-bangumi-1.2.11-arm64-v8a.apk.part');
      final foreign = await create('user-document.txt', stale: true);
      await pruneUpdateFiles(folder, keep: current.path);
      for (final retained in [current, previous, active, foreign]) {
        expect(await retained.exists(), true);
      }
      expect(await older.exists(), false);
      expect(await stalePart.exists(), false);
    },
  );
  test('temporary image cleanup only removes stale owned fragments', () async {
    final root = await Directory.systemTemp.createTemp('bgm-transfer-test-');
    addTearDown(() => root.delete(recursive: true));
    final files = ImageTransferFiles(directory: root);
    final active = await files.create();
    await active.writeAsString('active');
    final staleDir = await Directory('${root.path}/transfer-old').create();
    final stale = await File(
      '${staleDir.path}/image.part',
    ).writeAsString('old');
    final foreign = await File('${root.path}/notes.txt').writeAsString('keep');
    final old = DateTime.now().subtract(const Duration(days: 2));
    await stale.setLastModified(old);
    await active.setLastModified(old);
    await files.prune();
    expect(await stale.exists(), false);
    expect(await active.exists(), true);
    expect(await foreign.exists(), true);
    await files.release(active);
    expect(await active.parent.exists(), false);
  });
}

class _RealHttpOverrides extends HttpOverrides {}
