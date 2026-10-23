import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/app/state/session_scope.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/media/rich_image_policy.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/paged.dart';
import 'package:bangumi_flutter/core/subject_detail_models.dart';
import 'package:bangumi_flutter/core/text/bbcode_document.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/core/network/app_image_cache.dart';
import 'package:bangumi_flutter/domain/repositories/episode_progress_repository.dart';
import 'package:bangumi_flutter/features/blog/blog_detail_page.dart';
import 'package:bangumi_flutter/features/subject/episode_progress_controller.dart';
import 'package:bangumi_flutter/widgets/episode_progress_panel.dart';
import 'package:bangumi_flutter/widgets/lazy_tab_view.dart';
import 'package:bangumi_flutter/widgets/rich_comment_image.dart';
import 'package:bangumi_flutter/widgets/common.dart';
import 'comment_experience_test.dart' show host;
import 'notification_composer_viewer_test.dart' show UnavailableImageCache;

const photos = [
  {
    'id': 174070,
    'target': 'de/01/5799_EWl2L.jpg',
    'icon': 'https://lain.bgm.tv/r/200x200/pic/photo/l/de/01/5799_EWl2L.jpg',
  },
  {
    'id': 174069,
    'target': 'de/01/5799_hr7II.jpg',
    'icon': 'https://lain.bgm.tv/r/200x200/pic/photo/l/de/01/5799_hr7II.jpg',
  },
];
http.Response json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);
RemoteBangumiRepository blogRepository({
  String? body,
  bool failPhotos = false,
  int total = 2,
  List<String>? requests,
  bool withSubjects = false,
}) => RemoteBangumiRepository(
  apiClient: ApiClient(
    client: MockClient((request) async {
      requests?.add(request.url.toString());
      if (request.url.path.endsWith('/photos')) {
        if (failPhotos) return http.Response('', 503);
        final offset = int.parse(request.url.queryParameters['offset']!);
        return json({
          'data':
              offset == 0
                  ? photos
                  : [
                    {'id': 174068, 'target': 'de/01/5799_next.jpg'},
                  ],
          'total': total,
        });
      }
      if (request.url.path.endsWith('/subjects') && withSubjects) {
        return json([
          {
            'id': 42,
            'name': '关联作品 · Related work',
            'images': {'large': 'https://lain.bgm.tv/fixture-cover.jpg'},
          },
        ]);
      }
      if (request.url.path.endsWith('/subjects') ||
          request.url.path.endsWith('/comments')) {
        return json([]);
      }
      return json({
        'id': 381599,
        'title': '阅读的距离 · 一篇日志',
        'content': body ?? '正文没有图片标签。\n\n相册来自独立接口。',
        'user': {'username': 'fixture', 'nickname': '记录者'},
        'createdAt': 1791912658,
      });
    }),
  ),
);

void main() {
  setUpAll(() => AppImageCache.testManager = UnavailableImageCache());
  setUp(() async {
    final previous = AppImageCache.manager;
    AppImageCache.testManager = UnavailableImageCache();
    addTearDown(() => AppImageCache.testManager = previous);
    await RichImagePolicy.instance.initialize(MemorySecureVault());
  });
  test(
    '381599 independent photo envelope preserves original images and offset pagination',
    () async {
      final requests = <String>[];
      final repo = blogRepository(total: 3, requests: requests);
      addTearDown(repo.close);
      final detail = await repo.fetchBlog(381599);
      expect(detail.photos.map((photo) => photo.id), [174070, 174069]);
      expect(detail.photoTotal, 3);
      expect(
        detail.photos.first.originalUrl.toString(),
        'https://lain.bgm.tv/pic/photo/l/de/01/5799_EWl2L.jpg',
      );
      expect(requests.where((url) => url.contains('/photos')).length, 1);
      final page = await repo.fetchBlogPhotos(381599, offset: 2);
      expect(page.items.single.id, 174068);
      expect(page.hasMore, isFalse);
      expect(requests.last, contains('offset=2'));
    },
  );
  test(
    'photo failure is distinct from an empty gallery and body remains readable',
    () async {
      final repo = blogRepository(failPhotos: true);
      addTearDown(repo.close);
      final detail = await repo.fetchBlog(381599);
      expect(detail.blog.content, isNotEmpty);
      expect(detail.errors.keys, contains('photos'));
      final empty = RemoteBangumiRepository(
        apiClient: ApiClient(
          client: MockClient(
            (request) async =>
                request.url.path.endsWith('/photos')
                    ? json({'data': [], 'total': 0})
                    : request.url.path.endsWith('/381599')
                    ? json({'id': 381599, 'user': {}})
                    : json([]),
          ),
        ),
      );
      addTearDown(empty.close);
      expect((await empty.fetchBlog(381599)).errors, isEmpty);
    },
  );
  test('empty nonterminal and duplicate photo pages are rejected', () async {
    for (final data in [
      [],
      [photos.first, photos.first],
    ]) {
      final repo = RemoteBangumiRepository(
        apiClient: ApiClient(
          client: MockClient((_) async => json({'data': data, 'total': 10})),
        ),
      );
      await expectLater(
        repo.fetchBlogPhotos(381599),
        throwsA(isA<ApiException>()),
      );
      repo.close();
    }
  });
  test('photo BBCode allows only verified relative CDN paths', () {
    final doc = BangumiBbCode.parse(
      '[photo=159280]c0/43/427735_iLiyB.jpg[/photo]',
    );
    expect(doc.nodes.single.tag, 'photo');
    expect(
      BangumiBbCode.photoUrl(r'c0\/43\/427735\_iLiyB.jpg')?.toString(),
      'https://lain.bgm.tv/pic/photo/l/c0/43/427735_iLiyB.jpg',
    );
    expect(
      BangumiBbCode.photoUrl('c0/43/427735&#95;iLiyB.jpg')?.toString(),
      'https://lain.bgm.tv/pic/photo/l/c0/43/427735_iLiyB.jpg',
    );
    expect(
      BangumiBbCode.photoUrl(
        BangumiBbCode.plain(doc.nodes.single.children),
      ).toString(),
      'https://lain.bgm.tv/pic/photo/l/c0/43/427735_iLiyB.jpg',
    );
    for (final value in [
      '../de/01/a.jpg',
      'de/01/../a.jpg',
      'de/01/a.jpg?x=1',
      'de/01/a.jpg#x',
      '%64e/01/a.jpg',
      'de%2f01/a.jpg',
      'https://evil.test/a.jpg',
      '//evil.test/a.jpg',
      'de\\01\\a.jpg',
      'de/01/a%252e.jpg',
    ]) {
      expect(BangumiBbCode.photoUrl(value), isNull, reason: value);
    }
  });
  test('lazy blocks preserve style ancestors, one quote and atomic masks', () {
    final doc = BangumiBbCode.parse(
      '[b][color=red]one\ntwo[/color][/b]\n[quote]普通[b]加粗[/b]尾句[/quote]\n[mask]secret\nsecret2[/mask]',
    );
    final blocks = BangumiBbCode.blocks(doc);
    expect(blocks.length, 4);
    expect(blocks[1].single.tag, 'b');
    expect(blocks[1].single.children.single.tag, 'color');
    expect(blocks[2].single.tag, 'quote');
    expect(BangumiBbCode.plain(blocks[2]), '普通加粗尾句');
    expect(BangumiBbCode.plain(blocks[3]), '•••');
    final bounded = BangumiBbCode.parse(
      '[mask]${List.filled(70000, 'x').join()}',
    );
    expect(bounded.truncated, isTrue);
    expect(
      BangumiBbCode.plain(
        BangumiBbCode.blocks(bounded).expand((block) => block),
      ),
      '•••',
    );
  });
  testWidgets('body photo and independent gallery are deduplicated', (
    tester,
  ) async {
    final repo = blogRepository(
      body: '[photo=174070]de/01/5799_EWl2L.jpg[/photo]',
    );
    addTearDown(repo.close);
    await tester.pumpWidget(host(BlogDetailPage(id: 381599, repository: repo)));
    await tester.pumpAndSettle();
    final images = tester.widgetList<RichCommentImage>(
      find.byType(RichCommentImage),
    );
    expect(images.map((image) => image.uri.toString()).toSet().length, 2);
    expect(images.length, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('initial gallery error precedes comments and appears only once', (
    tester,
  ) async {
    final repo = blogRepository(failPhotos: true);
    addTearDown(repo.close);
    await tester.pumpWidget(host(BlogDetailPage(id: 381599, repository: repo)));
    await tester.pumpAndSettle();
    expect(find.byType(NetworkErrorView), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(NetworkErrorView)).dy,
      lessThan(tester.getTopLeft(find.text('评论')).dy),
    );
    expect(find.text('正文没有图片标签。', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('long article mounts only visible paragraphs and no far images', (
    tester,
  ) async {
    final repo = blogRepository(
      body:
          '${List.generate(500, (i) => 'Paragraph $i').join('\n')}\n[img]https://example.org/far.jpg[/img]',
    );
    addTearDown(repo.close);
    await tester.pumpWidget(host(BlogDetailPage(id: 381599, repository: repo)));
    await tester.pumpAndSettle();
    expect(find.byType(RichCommentImage), findsNothing);
    expect(find.text('Paragraph 499', findRichText: true), findsNothing);
    expect(tester.widgetList(find.byType(RichText)).length, lessThan(80));
    expect(tester.takeException(), isNull);
  });
  testWidgets('gallery continuation appends originals', (tester) async {
    final requests = <String>[];
    final repo = blogRepository(total: 3, requests: requests);
    addTearDown(repo.close);
    await tester.pumpWidget(host(BlogDetailPage(id: 381599, repository: repo)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('继续加载相册图片'), 300);
    await tester.tap(find.text('继续加载相册图片'));
    await tester.pumpAndSettle();
    expect(requests.where((url) => url.contains('/photos')).length, 2);
    expect(find.text('继续加载相册图片'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'gallery continuation failure retries without reloading the article',
    (tester) async {
      var articleReads = 0;
      var continuationReads = 0;
      final repo = RemoteBangumiRepository(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/photos')) {
              if (request.url.queryParameters['offset'] == '2') {
                continuationReads++;
                if (continuationReads == 1) return http.Response('', 403);
                return json({
                  'data': [
                    {'id': 3, 'target': 'de/01/5799_next.jpg'},
                  ],
                  'total': 3,
                });
              }
              return json({'data': photos, 'total': 3});
            }
            if (request.url.path.endsWith('/381599')) {
              articleReads++;
              return json({
                'id': 381599,
                'title': 'Readable article',
                'content': 'Retained body',
                'user': {},
              });
            }
            return json([]);
          }),
        ),
      );
      addTearDown(repo.close);
      await tester.pumpWidget(
        host(BlogDetailPage(id: 381599, repository: repo)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('继续加载相册图片'), 300);
      await tester.tap(find.text('继续加载相册图片'));
      await tester.pumpAndSettle();
      expect(find.byType(NetworkErrorView), findsOneWidget);
      final retry = find.descendant(
        of: find.byType(NetworkErrorView),
        matching: find.text('重试'),
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(continuationReads, 2);
      expect(articleReads, 1);
      expect(find.byType(NetworkErrorView), findsNothing);
    },
  );
  for (final (name, size, scale) in [
    ('desktop', const Size(1440, 1000), 1.0),
    ('mobile-large', const Size(390, 844), 1.6),
  ]) {
    testWidgets('reading layout $name has bounded width and no overflow', (
      tester,
    ) async {
      if (const bool.fromEnvironment('WRITE_VERIFICATION_IMAGES')) {
        await tester.runAsync(() async {
          for (final (family, path) in [
            (
              'MaterialIcons',
              'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ),
            ('Roboto', 'C:/Windows/Fonts/msyh.ttc'),
            ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
          ]) {
            final file = File(path);
            if (await file.exists()) {
              await (FontLoader(
                family,
              )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
            }
          }
        });
      }
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = blogRepository(
        withSubjects: true,
        body:
            '[b]正文应该有舒适的行距。[/b]\n${List.filled(8, '记录观看中的细节，也记录当时的心情。').join()}',
      );
      addTearDown(repo.close);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: host(
            BlogDetailPage(id: 381599, repository: repo),
            scale: scale,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ListView).first).width,
        lessThanOrEqualTo(880),
      );
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('WRITE_VERIFICATION_IMAGES')) {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/verification').create(recursive: true);
          await File(
            'build/verification/blog-$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
  testWidgets('full episode list lazily mounts rows and reaches last episode', (
    tester,
  ) async {
    final controller = EpisodeProgressController(_Episodes(), 1);
    await controller.refresh();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        Scaffold(
          body: EpisodeProgressPanel(
            controller: controller,
            repository: _Guest(),
            expanded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListTile).evaluate().length, lessThan(25));
    expect(find.byType(FilledButton), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Episode 999'),
      10000,
      maxScrolls: 20,
    );
    expect(find.text('Episode 999'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('overview limits episode buttons and exposes all chapters', (
    tester,
  ) async {
    final controller = EpisodeProgressController(_Episodes(), 1);
    await controller.refresh();
    addTearDown(controller.dispose);
    var opened = false;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: SingleChildScrollView(
            child: EpisodeProgressPanel(
              controller: controller,
              repository: _Guest(),
              onViewAll: () => opened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsNWidgets(24));
    await tester.ensureVisible(find.text('全部章节'));
    await tester.tap(find.text('全部章节'));
    expect(opened, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'tab animation reuses visited builders but parent update refreshes data',
    (tester) async {
      var builds = 0;
      late TabController tabs;
      Widget tree(String value) => host(
        DefaultTabController(
          length: 2,
          child: Builder(
            builder: (context) {
              tabs = DefaultTabController.of(context);
              return Scaffold(
                body: LazyTabView(
                  builders: [
                    () {
                      builds++;
                      return Text(value);
                    },
                    () {
                      builds++;
                      return const Text('second');
                    },
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpWidget(tree('first'));
      expect(builds, 1);
      tabs.animateTo(1);
      await tester.pumpAndSettle();
      expect(builds, 2);
      tabs.animateTo(0);
      await tester.pumpAndSettle();
      expect(builds, 2);
      await tester.pumpWidget(tree('updated'));
      await tester.pumpAndSettle();
      expect(find.text('updated'), findsOneWidget);
      expect(builds, 4);
    },
  );
  testWidgets('image retry evicts disk and bounded fit decode cache', (
    tester,
  ) async {
    final cache = _RetryCache();
    AppImageCache.testManager = cache;
    final uri = Uri.parse(
      'https://lain.bgm.tv/pic/photo/l/de/01/5799_retry.jpg',
    );
    await tester.pumpWidget(host(Scaffold(body: RichCommentImage(uri: uri))));
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    expect(provider.policy, ResizeImagePolicy.fit);
    expect(provider.width, lessThanOrEqualTo(2048));
    expect(provider.height, lessThanOrEqualTo(2048));
    final key = await provider.obtainKey(ImageConfiguration.empty);
    final pending = Completer<ImageInfo>();
    PaintingBinding.instance.imageCache.putIfAbsent(
      key,
      () => OneFrameImageStreamCompleter(pending.future),
    );
    expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(cache.removed, [uri.toString()]);
    expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
    expect(cache.reads, greaterThanOrEqualTo(2));
  });
  test(
    'live public blog 381599 exposes both independent photos',
    () async {
      final repo = RemoteBangumiRepository();
      addTearDown(repo.close);
      final detail = await repo.fetchBlog(381599);
      expect(detail.errors['photos'], isNull);
      expect(
        detail.photos.map((photo) => photo.id),
        containsAll([174070, 174069]),
      );
      expect(
        detail.photos.every((photo) => photo.originalUrl.host == 'lain.bgm.tv'),
        isTrue,
      );
    },
    skip:
        const bool.fromEnvironment('RUN_LIVE_BGM_TESTS')
            ? false
            : 'Live network probe',
  );
}

class _RetryCache extends UnavailableImageCache {
  final removed = <String>[];
  @override
  Future<void> removeFile(String key) async => removed.add(key);
}

class _Guest implements BangumiRepository {
  @override
  bool get isLoggedIn => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Episodes implements EpisodeProgressRepository {
  final changes = ChangeNotifier();
  @override
  SessionScope get scope =>
      const SessionScope(username: '', accountId: 0, epoch: 0);
  @override
  Listenable get sessionChanges => changes;
  @override
  Listenable get collectionChanges => changes;
  @override
  Future<bool> isCollected(int subjectId, {bool fresh = false}) async => false;
  @override
  Future<Paged<SubjectEpisode>> load(
    int subjectId, {
    int offset = 0,
    bool fresh = false,
  }) async => Paged(
    items: List.generate(
      1000,
      (index) => SubjectEpisode.fromJson({
        'id': index + 1,
        'sort': index + 1,
        'name': 'Episode $index',
      }),
    ),
    offset: 0,
    limit: 1000,
    total: 1000,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
