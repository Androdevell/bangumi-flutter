import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bangumi_flutter/app/bangumi_app.dart';
import 'package:bangumi_flutter/core/auth/auth_models.dart';
import 'package:bangumi_flutter/core/auth/auth_service.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/core/network/app_image_cache.dart';
import 'package:bangumi_flutter/core/network/cookie_session_client.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/features/auth/login_page.dart';
import 'package:bangumi_flutter/features/browse/browse_page.dart';
import 'package:bangumi_flutter/features/discover/discover_page.dart';
import 'package:bangumi_flutter/features/search/subject_search_delegate.dart';
import 'package:bangumi_flutter/features/shell/app_shell.dart';
import 'package:bangumi_flutter/features/timeline/timeline_page.dart';
import 'package:bangumi_flutter/widgets/comment_composer.dart';
import 'package:bangumi_flutter/widgets/common.dart';
import 'package:bangumi_flutter/widgets/subject_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  for (final timeline in [false, true]) {
    testWidgets(
      '${timeline ? "timeline" : "discover"} refresh invalidates cache and catches failure',
      (tester) async {
        var calls = 0;
        final repo = RemoteBangumiRepository(
          apiClient: ApiClient(
            client: MockClient((r) async {
              calls++;
              if (calls > 1) return http.Response('', 500);
              return _json(timeline ? [] : {});
            }),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body:
                  timeline
                      ? TimelinePage(repository: repo)
                      : DiscoverPage(repository: repo),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final refreshing =
            tester
                .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
                .show();
        await tester.pumpAndSettle();
        await refreshing;
        expect(calls, 2);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('服务器返回 500'), findsWidgets);
        await tester.pumpWidget(const SizedBox.shrink());
        repo.close();
      },
    );
  }
  for (final width in [540.0, 1280.0]) {
    testWidgets(
      'back returns to discover and tab state survives at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var browseRequests = 0;
        final repo = RemoteBangumiRepository(
          apiClient: ApiClient(
            client: MockClient((r) async {
              if (r.url.path == '/p1/subjects') browseRequests++;
              if (r.url.path == '/p1/calendar') return _json({});
              if (r.url.path == '/p1/timeline') return _json([]);
              return _json({'data': []});
            }),
          ),
        );
        await tester.pumpWidget(BangumiApp(repository: repo));
        await tester.pumpAndSettle();
        expect(find.byType(BrowsePage, skipOffstage: false), findsNothing);
        expect(browseRequests, 0);
        final nav =
            width < 760
                ? find.byType(NavigationBar)
                : find.byType(NavigationRail);
        await tester.tap(
          find.descendant(of: nav, matching: find.text('浏览')).last,
        );
        await tester.pumpAndSettle();
        final before = tester.state(
          find.byType(BrowsePage, skipOffstage: false),
        );
        await Navigator.of(tester.element(find.byType(AppShell))).maybePop();
        await tester.pumpAndSettle();
        for (final label in ['浏览', '超展开', '我的']) {
          await tester.tap(
            find.descendant(of: nav, matching: find.text(label)).last,
          );
          await tester.pumpAndSettle();
          final scope = tester.widget<PopScope<Object?>>(
            find.byWidgetPredicate((w) => w is PopScope).first,
          );
          expect(scope.canPop, false);
          await Navigator.of(tester.element(find.byType(AppShell))).maybePop();
          await tester.pumpAndSettle();
          expect(
            tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
            0,
          );
        }
        expect(
          identical(
            before,
            tester.state(find.byType(BrowsePage, skipOffstage: false)),
          ),
          true,
        );
        expect(browseRequests, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        repo.close();
      },
    );
  }
  testWidgets('auth broadcast enables friend filter and logout resets it', (
    tester,
  ) async {
    final auth = _FakeAuth();
    final api = _AuthApi(
      auth,
      MockClient((r) async {
        if (r.url.path == '/p1/calendar') return _json({});
        if (r.url.path == '/p1/timeline' || r.url.path.endsWith('/timeline')) {
          return _json([]);
        }
        if (r.url.path == '/p1/users/tester') {
          return _json({'username': 'tester'});
        }
        return _json({'data': []});
      }),
    );
    final repo = RemoteBangumiRepository(apiClient: api);
    await tester.pumpWidget(BangumiApp(repository: repo, authService: auth));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(Icons.view_timeline_outlined),
      ),
    );
    await tester.pumpAndSettle();
    Finder filter() => find.descendant(
      of: find.byType(TimelinePage, skipOffstage: false),
      matching: find.byWidgetPredicate(
        (w) => w is SegmentedButton<int>,
        skipOffstage: false,
      ),
      skipOffstage: false,
    );
    expect(
      tester.widget<SegmentedButton<int>>(filter()).segments[1].enabled,
      false,
    );
    auth.setLogged(true);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SegmentedButton<int>>(filter()).segments[1].enabled,
      true,
    );
    await tester.tap(find.text('好友'));
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<int>>(filter()).selected, {1});
    auth.setLogged(false);
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<int>>(filter()).selected, {0});
    expect(
      tester.widget<SegmentedButton<int>>(filter()).segments[1].enabled,
      false,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    repo.close();
    auth.dispose();
  });
  testWidgets('six typed characters cause one search and errors expose retry', (
    tester,
  ) async {
    final keywords = <String>[];
    var fail = false;
    final repo = RemoteBangumiRepository(
      apiClient: ApiClient(
        client: MockClient((r) async {
          keywords.add('${(jsonDecode(r.body) as Map)['keyword']}');
          if (fail) return http.Response('', 500);
          return _json({
            'data': [
              {'id': 1, 'name': 'result'},
            ],
            'offset': 0,
            'limit': 30,
            'total': 1,
          });
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed:
                      () => showSearch(
                        context: context,
                        delegate: SubjectSearchDelegate(repository: repo),
                      ),
                  child: const Text('Search'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    for (var i = 1; i <= 6; i++) {
      await tester.enterText(find.byType(TextField), 'abcdef'.substring(0, i));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(keywords, isEmpty);
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pumpAndSettle();
    expect(keywords, ['abcdef']);
    expect(find.text('result'), findsWidgets);
    fail = true;
    await tester.enterText(find.byType(TextField), 'offline');
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pumpAndSettle();
    expect(find.byType(NetworkErrorView), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('result'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.close();
  });
  testWidgets('browse scroll paginates and type filter resets to first page', (
    tester,
  ) async {
    final pages = <String>[];
    final types = <String>[];
    final repo = RemoteBangumiRepository(
      apiClient: ApiClient(
        client: MockClient((r) async {
          final p = int.parse(r.url.queryParameters['page']!);
          pages.add('$p');
          types.add(r.url.queryParameters['type']!);
          return _json({
            'data': [
              for (var i = 0; i < 4; i++)
                {'id': (p - 1) * 4 + i + 1, 'name': 'subject-$p-$i'},
            ],
            'offset': (p - 1) * 4,
            'limit': 4,
            'total': 8,
          });
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: BrowsePage(repository: repo))),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(pages, ['1', '2']);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 1500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书籍'));
    await tester.pumpAndSettle();
    expect(pages.last, '1');
    expect(types.last, '1');
    await tester.pumpWidget(const SizedBox.shrink());
    repo.close();
  });
  testWidgets(
    'composer can close repeatedly without disposed controller errors',
    (tester) async {
      final results = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      results.add(
                        await showCommentComposer(
                          context,
                          title: 'comment',
                          hint: 'hint',
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), ' reply-$i ');
        await tester.pump();
        await tester.tap(find.text(i.isEven ? '发布' : '取消'));
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(results.length, i + 1);
        expect(tester.takeException(), isNull);
        expect(results.last, i.isEven ? 'reply-$i' : null);
      }
    },
  );
  testWidgets('rapid captcha taps serialize challenge and disable login', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(MaterialApp(home: LoginPage(authService: auth)));
    await tester.pumpAndSettle();
    expect(auth.beginCalls, 1);
    auth.gate = Completer<LoginChallenge>();
    final captcha = find.byTooltip('刷新验证码');
    await tester.tap(captcha);
    for (var i = 0; i < 9; i++) {
      await tester.tap(captcha);
    }
    await tester.pump();
    expect(auth.beginCalls, 2);
    expect(
      tester
          .widget<FilledButton>(
            find.byWidgetPredicate((w) => w is FilledButton),
          )
          .onPressed,
      isNull,
    );
    auth.gate!.complete(const LoginChallenge({'token': 'second'}));
    await tester.pumpAndSettle();
    expect(auth.captchaCalls, 2);
    expect(
      tester
          .widget<FilledButton>(
            find.byWidgetPredicate((w) => w is FilledButton),
          )
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  });
  testWidgets('SectionHeader supports large text without phantom actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3)),
            child: const SectionHeader(title: '大字号标题', actionLabel: '不存在的操作'),
          ),
        ),
      ),
    );
    expect(find.text('不存在的操作'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('image cache initialization is idempotent and capped at 64 MB', (
    tester,
  ) async {
    final client = MockClient((_) async => http.Response('', 404));
    AppImageCache.initialize(client);
    final first = AppImageCache.manager;
    AppImageCache.initialize(client);
    expect(identical(first, AppImageCache.manager), true);
    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 64 << 20);
  });
  testWidgets(
    'same subject twice has independent Hero tags and callback navigation',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                for (final tag in ['first', 'second'])
                  Expanded(
                    child: SubjectCard(
                      subject: const Subject(id: 1, title: 'same'),
                      heroTag: tag,
                      onTap: () {
                        taps++;
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.widgetList<Hero>(find.byType(Hero)).map((h) => h.tag).toList(),
        ['first', 'second'],
      );
      await tester.tap(find.text('same').first);
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

class _AuthApi extends ApiClient {
  _AuthApi(this.auth, http.Client client)
    : super(client: client, authService: auth);
  final _FakeAuth auth;
  @override
  bool get isLoggedIn => auth.isLoggedIn;
  @override
  String get currentUsername => auth.isLoggedIn ? 'tester' : '';
}

class _FakeAuth extends AuthService {
  _FakeAuth()
    : super(
        client: MockClient((_) async => http.Response('', 200)),
        cookies: PersistentCookieStore(MemorySecureVault()),
        vault: MemorySecureVault(),
      );
  bool logged = false;
  int beginCalls = 0;
  int captchaCalls = 0;
  Completer<LoginChallenge>? gate;
  void setLogged(bool value) {
    logged = value;
    notifyListeners();
  }

  @override
  bool get isLoggedIn => logged;
  @override
  AuthUser? get user =>
      logged
          ? const AuthUser(username: 'tester', nickname: 'tester', formHash: '')
          : null;
  @override
  Future<String?> validAccessToken() async => null;
  @override
  Future<LoginChallenge> beginLogin({String? expectedUsername}) async {
    beginCalls++;
    return gate?.future ??
        Future.value(const LoginChallenge({'token': 'first'}));
  }

  @override
  Future<Uint8List> loadCaptcha() async {
    captchaCalls++;
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jA1sAAAAASUVORK5CYII=',
    );
  }
}
