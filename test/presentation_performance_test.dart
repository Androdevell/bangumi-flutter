import 'dart:async';
import 'dart:convert';
import 'package:bangumi_flutter/app/bangumi_app.dart';
import 'package:bangumi_flutter/app/app_motion.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/cache/calendar_snapshot.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/network/cookie_session_client.dart';
import 'package:bangumi_flutter/core/network/platform_http_client.dart';
import 'package:bangumi_flutter/core/settings/app_preferences.dart';
import 'package:bangumi_flutter/core/text/bbcode_document.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/features/subject/subject_detail_page.dart';
import 'package:bangumi_flutter/features/user/user_profile_page.dart';
import 'package:bangumi_flutter/features/discover/discover_controller.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/widgets/bangumi_rich_text.dart';
import 'package:bangumi_flutter/widgets/subject_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object data) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), 200);
Iterable<ComposeRichTextNode> flatten(List<ComposeRichTextNode> nodes) sync* {
  for (final node in nodes) {
    yield node;
    yield* flatten(node.children);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'expired public cache preserves single-flight and late failure cannot clear refresh',
    () async {
      var now = DateTime.utc(2026);
      final responses = <Completer<http.Response>>[];
      final api = ApiClient(
        clock: () => now,
        client: MockClient((_) {
          final response = Completer<http.Response>();
          responses.add(response);
          return response.future;
        }),
      );
      final initial = api.publicCalendar();
      await Future<void>.delayed(Duration.zero);
      responses[0].complete(json({}));
      await initial;
      now = now.add(const Duration(minutes: 6));
      final old = api.publicCalendar();
      final merged = api.publicCalendar();
      expect(identical(old, merged), true);
      final failure = expectLater(old, throwsA(isA<ApiException>()));
      api.invalidateResources({'p1/calendar'});
      final fresh = api.publicCalendar();
      await Future<void>.delayed(Duration.zero);
      responses[2].complete(json({'Mon': []}));
      await fresh;
      responses[1].complete(http.Response('', 500));
      await failure;
      await api.publicCalendar();
      expect(responses.length, 3);
      api.close();
    },
  );
  test(
    'cached calendar stays readable after refresh failure and disposed controller ignores late success',
    () async {
      final repo = _CalendarRepo();
      final controller = DiscoverController(repo)..dispatch(LoadDiscover());
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.calendar!['Mon']!.single.id, 1);
      expect(controller.state.cached, true);
      repo.next.completeError(const ApiException('offline'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.error, isA<ApiException>());
      expect(controller.state.calendar!['Mon']!.single.id, 1);
      repo.next = Completer<Map<String, List<Subject>>>();
      final refreshing = controller.refresh();
      controller.dispose();
      repo.next.complete({});
      await refreshing;
      expect(controller.state.calendar!['Mon']!.single.id, 1);
    },
  );
  testWidgets(
    'nested styles reach rendered spans in narrow dark large-text layout',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
              body: SizedBox(
                width: 320,
                child: BangumiRichText(
                  '[b][color=red][size=18]styled[/size][/color][/b] [u][s]decorated[/s][/u] <ゝω·',
                ),
              ),
            ),
          ),
        ),
      );
      final spans = tester.widgetList<RichText>(find.byType(RichText)).expand((
        widget,
      ) {
        Iterable<TextSpan> walk(InlineSpan span) sync* {
          if (span is TextSpan) {
            yield span;
            for (final child in span.children ?? <InlineSpan>[]) {
              yield* walk(child);
            }
          }
        }

        return walk(widget.text);
      });
      final styled = spans.firstWhere((span) => span.text == 'styled');
      expect(styled.style!.fontWeight, FontWeight.bold);
      expect(styled.style!.fontSize, 18);
      final decorated = spans.firstWhere((span) => span.text == 'decorated');
      expect(
        decorated.style!.decoration!.contains(TextDecoration.underline),
        true,
      );
      expect(
        decorated.style!.decoration!.contains(TextDecoration.lineThrough),
        true,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('long card title fits narrow card with large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SizedBox(
              width: 148,
              height: 300,
              child: SubjectCard(
                subject: const Subject(
                  id: 1,
                  title: 'very long title 日本語 中文作品标题',
                  subtitle: 'subtitle',
                  episodes: 12,
                ),
                heroTag: 'narrow',
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
  test(
    'nested BBCode retains style tree, Unicode and redacts masks in plain output',
    () {
      final doc = BangumiBbCode.parse(
        '[b][color=red][size=18]标题[/size][/color][/b]\r\n[mask]秘密[/mask][s]旧[/s][u]新[/u] <ゝω· &amp;',
      );
      expect(
        flatten(doc.nodes).map((n) => n.tag),
        containsAll(['b', 'color', 'size', 'mask', 's', 'u']),
      );
      expect(BangumiBbCode.plain(doc.nodes), contains('标题\n•••旧新 <ゝω· &'));
      expect(BangumiBbCode.plain(doc.nodes), isNot(contains('秘密')));
      expect(
        () => doc.nodes.add(ComposeRichTextNode('text', '', [])),
        throwsUnsupportedError,
      );
    },
  );
  test('malformed, unknown and excessive nesting remain safe', () {
    expect(
      BangumiBbCode.plain(BangumiBbCode.parse('x[unknown]y[/unknown]').nodes),
      'x[unknown]y[/unknown]',
    );
    expect(
      BangumiBbCode.plain(
        BangumiBbCode.parse('[mask]secret without closing').nodes,
      ),
      '•••',
    );
    final doc = BangumiBbCode.parse(
      '${List.filled(20, '[b]').join()}[mask]secret[/mask]',
    );
    expect(doc.truncated, true);
    expect(BangumiBbCode.plain(doc.nodes), isNot(contains('secret')));
  });
  test('unsafe URLs are rejected and escaped photo URLs remain supported', () {
    for (final value in [
      'javascript:alert(1)',
      'data:image/png,abc',
      'file:///a',
      'https://127.0.0.1/a',
      'https://localhost/a',
      'https://name:pass@example.org/a',
    ]) {
      expect(BangumiBbCode.safeUrl(value), isNull);
    }
    expect(
      BangumiBbCode.safeUrl(r'//lain.bgm.tv/a\_b.jpg')!.toString(),
      'https://lain.bgm.tv/a_b.jpg',
    );
  });
  testWidgets('spoiler is not rendered or exposed before explicit reveal', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BangumiRichText('[b]标题[/b] [mask][u]private text[/u][/mask]'),
        ),
      ),
    );
    expect(
      find.textContaining('private text', findRichText: true),
      findsNothing,
    );
    expect(find.bySemanticsLabel(RegExp('private text')), findsNothing);
    await tester.tap(find.text('•••'));
    await tester.pump();
    expect(
      find.textContaining('private text', findRichText: true),
      findsWidgets,
    );
    semantics.dispose();
  });
  test(
    'public calendar bypasses saved cookies and credentials, merges reads and refreshes',
    () async {
      var calls = 0;
      final cookies = PersistentCookieStore(MemorySecureVault());
      await cookies.initialize();
      await cookies.capture(
        Uri.parse('https://next.bgm.tv/'),
        'session=private; Path=/; Secure',
      );
      final api = ApiClient(
        client: CookieSessionClient(
          MockClient((request) async {
            calls++;
            expect(request.headers['cookie'], isNull);
            expect(request.headers['authorization'], isNull);
            return json({});
          }),
          cookies,
        ),
      );
      await Future.wait([api.publicCalendar(), api.publicCalendar()]);
      expect(calls, 1);
      api.invalidateResources({'p1/calendar'});
      await api.publicCalendar();
      expect(calls, 2);
      api.close();
    },
  );
  test('read deadline covers pending transport and triggers abort', () async {
    final aborted = Completer<void>();
    final api = ApiClient(
      readBudget: const Duration(milliseconds: 300),
      client: MockClient.streaming((request, _) async {
        final abortable = request as http.Abortable;
        await abortable.abortTrigger;
        aborted.complete();
        throw http.RequestAbortedException(request.url);
      }),
    );
    await expectLater(api.get('p1/subjects/1'), throwsA(isA<ApiException>()));
    await aborted.future.timeout(const Duration(seconds: 1));
    api.close();
  });
  test(
    'calendar snapshot isolates environment, expires and ignores malformed cache',
    () async {
      final vault = MemorySecureVault();
      final store = CalendarSnapshotStore(vault, 'https://next.bgm.tv/');
      await store.write({'Sun': []});
      expect((await store.read())!.data['Sun'], isEmpty);
      expect(
        await CalendarSnapshotStore(vault, 'https://other.example/').read(),
        isNull,
      );
      await vault.write(CalendarSnapshotStore.key, '{bad');
      expect(await store.read(), isNull);
      await vault.write(
        CalendarSnapshotStore.key,
        jsonEncode({
          'version': 1,
          'environment': store.environment,
          'at':
              DateTime.now()
                  .subtract(const Duration(days: 5))
                  .toIso8601String(),
          'data': {},
        }),
      );
      expect(await store.read(), isNull);
    },
  );
  test('reduced motion preference survives reload', () async {
    final prefs = AppPreferences(MemorySecureVault());
    expect((await prefs.load()).reduceMotion, false);
    await prefs.setReduceMotion(true);
    expect((await prefs.load()).reduceMotion, true);
  });
  testWidgets('motion policy honors application and system reduction', (
    tester,
  ) async {
    bool value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AppMotionPolicy(
          reduced: true,
          child: Builder(
            builder: (context) {
              value = AppMotionPolicy.reduce(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(value, true);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: AppMotionPolicy(
            reduced: false,
            child: Builder(
              builder: (context) {
                value = AppMotionPolicy.duration(context, 200) == Duration.zero;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    expect(value, true);
  });
  testWidgets(
    'cold shell reads only calendar; visited page state is retained',
    (tester) async {
      final paths = <String>[];
      final repo = RemoteBangumiRepository(
        apiClient: ApiClient(
          client: MockClient((request) async {
            paths.add(request.url.path);
            if (request.url.path == '/p1/calendar') return json({});
            if (request.url.path == '/p1/timeline') return json([]);
            return json({'data': []});
          }),
        ),
      );
      await tester.pumpWidget(BangumiApp(repository: repo));
      await tester.pumpAndSettle();
      expect(paths, ['/p1/calendar']);
      final nav = find.byType(NavigationRail);
      await tester.tap(
        find.descendant(
          of: nav,
          matching: find.byIcon(Icons.view_timeline_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(paths, ['/p1/calendar', '/p1/timeline']);
      await tester.tap(
        find.descendant(of: nav, matching: find.byIcon(Icons.home_outlined)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: nav,
          matching: find.byIcon(Icons.view_timeline_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(paths.length, 2);
      await tester.pumpWidget(const SizedBox());
      repo.close();
    },
  );
  testWidgets(
    'summary renders while progress is pending and chapter tab reuses its request',
    (tester) async {
      final paths = <String>[];
      final chapters = Completer<http.Response>();
      final repo = RemoteBangumiRepository(
        apiClient: ApiClient(
          client: MockClient((request) async {
            paths.add(request.url.path);
            if (request.url.path == '/p1/subjects/42/episodes') {
              return chapters.future;
            }
            if (request.url.path == '/p1/subjects/42') {
              return json({
                'id': 42,
                'name': 'Subject',
                'summary': 'Immediate summary',
                'type': 2,
              });
            }
            return json({'data': []});
          }),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SubjectDetailPage(
            subject: const Subject(id: 42, title: 'Subject'),
            heroTag: 'test42',
            repository: repo,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(paths.toSet(), {'/p1/subjects/42', '/p1/subjects/42/episodes'});
      expect(
        find.textContaining('Immediate summary', findRichText: true),
        findsWidgets,
      );
      chapters.complete(json({'data': [], 'total': 0}));
      await tester.pumpAndSettle();
      await tester.tap(find.text('章节'));
      await tester.pumpAndSettle();
      expect(paths.where((p) => p.endsWith('/episodes')).length, 1);
      await tester.pumpWidget(const SizedBox());
      repo.close();
    },
  );
  testWidgets('user biography is visible while unrelated requests are absent', (
    tester,
  ) async {
    final paths = <String>[];
    final pending = Completer<http.Response>();
    final repo = RemoteBangumiRepository(
      apiClient: ApiClient(
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/p1/users/u') {
            return json({
              'id': 1,
              'username': 'u',
              'nickname': 'User',
              'bio': '[b]Visible biography[/b]',
              'stats': {'subject': {}},
            });
          }
          return pending.future;
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: UserProfilePage(username: 'u', repository: repo)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Visible biography', findRichText: true), findsWidgets);
    expect(
      paths.where(
        (path) =>
            path.contains('friends') ||
            path.contains('blogs') ||
            path.contains('characters'),
      ),
      isEmpty,
    );
    pending.complete(json({'data': []}));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    repo.close();
  });
  test(
    'Android abort trigger reaches native cancelRequest exactly once',
    () async {
      const channel = MethodChannel('com.xiaoyv.bangumi/network');
      final pending = Completer<Map<String, Object>>();
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            if (call.method == 'cancelRequest') {
              pending.completeError(PlatformException(code: 'cancelled'));
              return null;
            }
            return pending.future;
          });
      final abort = Completer<void>();
      final client = AndroidBangumiHttpClient();
      final request = client.send(
        http.AbortableRequest(
          'GET',
          Uri.parse('https://next.bgm.tv/p1/calendar'),
          abortTrigger: abort.future,
        ),
      );
      final expectation = expectLater(
        request,
        throwsA(isA<http.RequestAbortedException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      abort.complete();
      await expectation;
      expect(methods, ['request', 'cancelRequest']);
      client.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}

class _CalendarRepo implements BangumiRepository, CalendarSnapshotRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository call');
  Completer<Map<String, List<Subject>>> next = Completer();
  @override
  Future<Map<String, List<Subject>>> fetchCalendar() => next.future;
  @override
  Future<Map<String, List<Subject>>> refreshCalendar() => next.future;
  @override
  Future<ComposeCalendarSnapshot?> readCalendarSnapshot() async =>
      ComposeCalendarSnapshot({
        'Mon': [const Subject(id: 1, title: 'cached')],
      }, DateTime.now());
}
