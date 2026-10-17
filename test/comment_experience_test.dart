import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/app/app_theme.dart';
import 'package:bangumi_flutter/core/community_models.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/cache/calendar_snapshot.dart';
import 'package:bangumi_flutter/widgets/bangumi_rich_text.dart';
import 'package:bangumi_flutter/core/localization/app_localizations.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/domain/use_cases/comment_submit_use_case.dart';
import 'package:bangumi_flutter/features/community/comment_composer_controller.dart';
import 'package:bangumi_flutter/features/community/comment_page_controller.dart';
import 'package:bangumi_flutter/features/community/community_widgets.dart';
import 'package:bangumi_flutter/features/discover/discover_page.dart';
import 'package:bangumi_flutter/features/subject/subject_detail_page.dart';
import 'package:bangumi_flutter/widgets/comment_composer.dart';
import 'package:bangumi_flutter/widgets/subject_card.dart';

CommentComposerController model({
  Future<void> Function(String)? send,
  bool Function()? current,
}) => CommentComposerController(
  maxLength: 1000,
  submit: send ?? (_) async {},
  isCurrent: current ?? () => true,
);
void edit(CommentComposerController controller, String text) =>
    controller.dispatch(
      EditComment(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      ),
    );
Widget host(
  Widget home, {
  String locale = 'zh',
  double scale = 1,
  double keyboard = 0,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light(),
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
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      ),
  home: home,
);
Widget editorHost(
  CommentComposerController controller, {
  String locale = 'zh',
  double scale = 1,
  double keyboard = 0,
}) => host(
  Builder(
    builder:
        (context) => Scaffold(
          body: TextButton(
            onPressed:
                () => showCommentComposer(
                  context,
                  title: AppLocalizations.of(context).t('postComment'),
                  hint: AppLocalizations.of(context).t('commentHint'),
                  target: '作品标题 / 第 12 话',
                  username: 'user',
                  controller: controller,
                ),
            child: const Text('open'),
          ),
        ),
  ),
  locale: locale,
  scale: scale,
  keyboard: keyboard,
);
CommunityReply reply(int id, {String? content}) => CommunityReply.fromJson({
  'id': id,
  'content': content ?? 'Comment $id [b]正文[/b]',
  'user': {'username': 'user', 'nickname': 'User'},
  'createdAt': 1780000000,
  'replies': [],
});

void main() {
  test(
    'confirmed publish supersedes a pre-publish read already in flight',
    () async {
      final requests = <Completer<List<int>>>[];
      final controller = CommentPageController<List<int>>(
        load: () {
          final request = Completer<List<int>>();
          requests.add(request);
          return request.future;
        },
        session: () => 'same',
      );
      final old = controller.refresh();
      final fresh = controller.refresh(afterPublish: true);
      requests[1].complete([1, 2]);
      await fresh;
      requests[0].complete([1]);
      await old;
      expect(controller.state.data, [1, 2]);
      controller.dispose();
    },
  );
  testWidgets(
    'cached homepage refresh has no visible loading text or layout shift',
    (tester) async {
      final day =
          [
            'Mon',
            'Tue',
            'Wed',
            'Thu',
            'Fri',
            'Sat',
            'Sun',
          ][DateTime.now().weekday - 1];
      final payload = {
        day: [
          {'id': 42, 'name': 'Cached subject', 'type': 2},
        ],
      };
      final store = CalendarSnapshotStore(
        MemorySecureVault(),
        'https://next.bgm.tv/',
      );
      await store.write(payload);
      final pending = Completer<http.Response>();
      final repo = RemoteBangumiRepository(
        calendarStore: store,
        apiClient: ApiClient(client: MockClient((_) => pending.future)),
      );
      await tester.pumpWidget(
        host(Scaffold(body: DiscoverPage(repository: repo))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('正在使用缓存'), findsNothing);
      expect(find.textContaining('更新时间'), findsNothing);
      expect(find.text('读取中'), findsNothing);
      final before = tester.getTopLeft(find.byType(SubjectCard).first);
      pending.complete(
        http.Response.bytes(utf8.encode(jsonEncode(payload)), 200),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(SubjectCard).first), before);
      await tester.pumpWidget(const SizedBox());
      repo.close();
    },
  );
  testWidgets(
    'unknown publishing stays open, is not resubmitted and fits large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var posts = 0;
      final controller = model(
        send: (_) async {
          posts++;
          throw const ApiException('unknown', outcomeUnknown: true);
        },
      );
      edit(controller, 'draft');
      controller.dispatch(SubmitComment());
      await tester.pump();
      await tester.pumpWidget(
        editorHost(controller, locale: 'en', scale: 2, keyboard: 240),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.canSubmit, false);
      controller.dispatch(SubmitComment());
      expect(posts, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('long links and revealed masks stay within narrow comment width', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          body: SizedBox(
            width: 220,
            child: BangumiRichText(
              '[url=https://example.org]${'longlink' * 20}[/url] [mask]${'secret ' * 30}[/mask]',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('•••'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  test(
    'formatting keeps selections, emoji boundaries, undo and IME composition',
    () {
      final controller = model();
      controller.dispatch(
        EditComment(
          const TextEditingValue(
            text: 'A😀B',
            selection: TextSelection(baseOffset: 2, extentOffset: 3),
          ),
        ),
      );
      controller.wrap('b');
      expect(controller.state.value.text, 'A[b]😀[/b]B');
      controller.undo();
      expect(controller.state.value.text, 'A😀B');
      controller.undo(redo: true);
      expect(controller.state.value.text, 'A[b]😀[/b]B');
      controller.dispatch(
        EditComment(
          const TextEditingValue(
            text: '中文',
            composing: TextRange(start: 0, end: 2),
          ),
        ),
      );
      controller.wrap('mask');
      expect(controller.state.value.text, '中文');
      expect(controller.canSubmit, false);
      controller.dispose();
    },
  );
  test(
    'submit is serialized and late success cannot notify disposed controller',
    () async {
      final pending = Completer<void>();
      var sent = 0;
      final controller = model(
        send: (_) {
          sent++;
          return pending.future;
        },
      );
      edit(controller, 'draft');
      controller.dispatch(SubmitComment());
      controller.dispatch(SubmitComment());
      expect(sent, 1);
      expect(controller.busy, true);
      controller.dispose();
      pending.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );
  test(
    'unknown response stays locked across edits until explicit verification',
    () async {
      final controller = model(
        send:
            (_) async =>
                throw const ApiException('unconfirmed', outcomeUnknown: true),
      );
      edit(controller, 'draft');
      controller.dispatch(SubmitComment());
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, CommentSubmitStatus.unknown);
      edit(controller, 'changed');
      expect(controller.canSubmit, false);
      controller.acknowledgeNotSent();
      expect(controller.canSubmit, true);
      controller.dispose();
    },
  );
  test(
    'known failure keeps content; account switch blocks both before and after send',
    () async {
      var current = true;
      final pending = Completer<void>();
      var sent = 0;
      final controller = model(
        current: () => current,
        send: (_) {
          sent++;
          return pending.future;
        },
      );
      edit(controller, 'draft');
      controller.dispatch(SubmitComment());
      current = false;
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, CommentSubmitStatus.stale);
      controller.dispatch(SubmitComment());
      expect(sent, 1);
      controller.dispose();
      final failed = model(
        send: (_) async => throw const ApiException('400', statusCode: 400),
      );
      edit(failed, 'draft');
      failed.dispatch(SubmitComment());
      await Future<void>.delayed(Duration.zero);
      expect(failed.state.status, CommentSubmitStatus.failed);
      expect(failed.state.value.text, 'draft');
      expect(failed.canSubmit, true);
      failed.dispose();
    },
  );
  test(
    'successful post and failed GET are independent and old content is retained',
    () async {
      var fail = false;
      final controller = CommentPageController<List<int>>(
        load: () async {
          if (fail) throw const ApiException('offline');
          return [1];
        },
        session: () => 'same',
      );
      await controller.refresh();
      fail = true;
      await controller.refresh(afterPublish: true);
      expect(controller.state.data, [1]);
      expect(controller.state.afterPublish, true);
      expect(controller.state.error, isNotNull);
      controller.dispose();
    },
  );
  test(
    'draft is bound to the opening account and unsupported targets never write',
    () async {
      final repo = _Repository();
      final useCase = CommentSubmitUseCase(
        repo,
        const ComposeCommentTarget.episode(1, 'episode'),
      );
      repo.currentUsername = 'another';
      await expectLater(useCase('draft'), throwsA(isA<ApiException>()));
      expect(repo.posts, 0);
      final unsupported = CommentSubmitUseCase(
        repo,
        ComposeCommentTarget.topic(
          const Topic(
            id: 2,
            type: 'person',
            title: 'read only',
            group: '',
            replies: 0,
            updatedAt: null,
          ),
        ),
      );
      await expectLater(unsupported('draft'), throwsA(isA<ApiException>()));
      expect(repo.posts, 0);
    },
  );
  test(
    'POST uncertainty does not invalidate the unrelated public calendar',
    () async {
      var calendars = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/p1/calendar') {
            calendars++;
            return http.Response('{}', 200);
          }
          return http.Response('<html>unclear</html>', 200);
        }),
      );
      await api.publicCalendar();
      await expectLater(
        api.postWebForm('new_reply', fields: {}),
        throwsA(
          isA<ApiException>().having((e) => e.outcomeUnknown, 'unknown', true),
        ),
      );
      await api.publicCalendar();
      expect(calendars, 1);
      api.close();
    },
  );
  for (final locale in ['zh', 'en', 'ja']) {
    testWidgets(
      'editor fits keyboard and large text in $locale; preview preserves hidden spoilers',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = model();
        edit(controller, '[b]Visible[/b][mask]secret-hidden[/mask]');
        await tester.pumpWidget(
          editorHost(controller, locale: locale, scale: 2, keyboard: 240),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final strings = AppLocalizations(Locale(locale));
        await tester.ensureVisible(find.text(strings.t('preview')));
        await tester.tap(find.text(strings.t('preview')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('secret-hidden', findRichText: true),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
  testWidgets('failed publish keeps editor open and draft can be reopened', (
    tester,
  ) async {
    final controller = model(
      send: (_) async => throw const ApiException('400', statusCode: 400),
    );
    edit(controller, 'my draft');
    await tester.pumpWidget(editorHost(controller));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('comment-input')), findsOneWidget);
    expect(controller.state.value.text, 'my draft');
    expect(controller.state.status, CommentSubmitStatus.failed);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留并关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('comment-input')))
          .controller!
          .text,
      'my draft',
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'reading layout fits long names and nested replies with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final nested = CommunityReply.fromJson({
        'id': 1,
        'content': 'Body [mask]secret[/mask]',
        'user': {'username': 'user', 'nickname': 'とても長い名前中文长昵称' * 3},
        'replies': [
          for (var i = 0; i < 5; i++)
            {
              'id': i + 2,
              'user': {'nickname': 'Reply', 'username': 'user'},
              'content': 'reply $i',
            },
        ],
      });
      await tester.pumpWidget(
        host(
          Scaffold(
            body: CommunityReplyList(
              items: [nested],
              currentUsername: 'user',
              authorUsername: 'user',
              onUserTap: (_) {},
              onLike: (_, _) async {},
            ),
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('secret', findRichText: true), findsNothing);
    },
  );
  for (final list in [false, true]) {
    testWidgets(
      'return from cards ten times retains homepage without reload; list=$list',
      (tester) async {
        var calendars = 0;
        final repo = RemoteBangumiRepository(
          apiClient: ApiClient(
            client: MockClient((request) async {
              if (request.url.path == '/p1/calendar') {
                calendars++;
                return http.Response.bytes(
                  utf8.encode(
                    jsonEncode({
                      [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ][DateTime.now().weekday - 1]: [
                        {'id': 42, 'name': 'Subject', 'type': 2},
                      ],
                    }),
                  ),
                  200,
                );
              }
              return http.Response(
                '{"id":42,"name":"Subject","type":2,"summary":"Summary"}',
                200,
              );
            }),
          ),
        );
        await tester.pumpWidget(
          host(Scaffold(body: DiscoverPage(repository: repo))),
        );
        await tester.pumpAndSettle();
        if (list) {
          await tester.tap(find.text('列表'));
          await tester.pumpAndSettle();
        }
        final before = tester.state(find.byType(DiscoverPage));
        for (var i = 0; i < 10; i++) {
          await tester.tap(find.text('Subject').first);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pumpAndSettle();
          expect(find.byType(SubjectDetailPage), findsOneWidget);
          expect(
            tester
                .widgetList<PosterArt>(find.byType(PosterArt))
                .every((p) => p.cacheWidth == SubjectPosterHero.decodeWidth),
            true,
          );
          await tester.tap(find.byType(BackButton));
          await tester.pump(const Duration(milliseconds: 80));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            identical(tester.state(find.byType(DiscoverPage)), before),
            true,
          );
        }
        expect(calendars, 1);
        expect(find.textContaining('正在使用缓存'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        repo.close();
      },
    );
  }
  testWidgets('editor and reading preview artifacts', (tester) async {
    if (!const bool.fromEnvironment('RENDER_COMMENT_PREVIEW')) return;
    await tester.runAsync(() async {
      final icons = File(
        'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (await icons.exists()) {
        final loader = FontLoader('MaterialIcons')..addFont(
          icons.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
        await loader.load();
      }
      final file = File('C:/Windows/Fonts/msyh.ttc');
      if (await file.exists()) {
        for (final family in ['Roboto', 'Microsoft YaHei UI']) {
          final loader = FontLoader(family)..addFont(
            file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
          await loader.load();
        }
      }
    });
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = model();
    edit(controller, '这集的演出很精彩！\n[b]画面和配乐都很喜欢[/b]\n[mask]这里是剧透内容[/mask]');
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('preview'),
        child: editorHost(controller),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await Directory('build/previews').create(recursive: true);
      await File(
        'build/previews/comment-editor.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(
      host(
        RepaintBoundary(
          key: const ValueKey('reading-preview'),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 850,
                child: CommunityReplyList(
                  items: [reply(1), reply(2), reply(3)],
                  currentUsername: 'user',
                  onUserTap: (_) {},
                  onLike: (_, _) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final reading =
          await tester
              .renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('reading-preview')),
              )
              .toImage();
      final readingBytes = await reading.toByteData(
        format: ui.ImageByteFormat.png,
      );
      reading.dispose();
      await File(
        'build/previews/comment-reading.png',
      ).writeAsBytes(readingBytes!.buffer.asUint8List());
    });
    controller.dispose();
  });
}

class _Repository implements BangumiRepository {
  @override
  String currentUsername = 'me';
  @override
  bool get isLoggedIn => true;
  int posts = 0;
  @override
  Future<void> createEpisodeComment(int episodeId, String content) async {
    posts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
