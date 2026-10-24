import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/app/state/session_scope.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/network/windows_system_client.dart';
import 'package:bangumi_flutter/core/community_models.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/core/paged.dart';
import 'package:bangumi_flutter/core/subject_detail_models.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/data/repositories/remote_private_message_repository.dart';
import 'package:bangumi_flutter/domain/models/blog.dart';
import 'package:bangumi_flutter/domain/repositories/blog_repository.dart';
import 'package:bangumi_flutter/domain/repositories/index_repository.dart';
import 'package:bangumi_flutter/domain/use_cases/comment_submit_use_case.dart';
import 'package:bangumi_flutter/features/blog/blog_detail_page.dart';
import 'package:bangumi_flutter/features/indexes/index_detail_page.dart';
import 'package:bangumi_flutter/features/episode/episode_comments_page.dart';
import 'package:bangumi_flutter/features/community/comment_sort.dart';
import 'package:bangumi_flutter/features/user/user_profile_page.dart';
import 'package:bangumi_flutter/widgets/subject_tag_chip.dart';
import 'package:bangumi_flutter/domain/repositories/private_message_repository.dart';
import 'package:bangumi_flutter/features/messages/private_messages_page.dart';
import 'comment_experience_test.dart' show host;

class ScopedApi extends ApiClient {
  ScopedApi(superClient) : super(client: superClient);
  SessionScope active = const SessionScope(
    username: 'fixture',
    accountId: 1,
    epoch: 1,
  );
  @override
  SessionScope get sessionScope => active;
  @override
  bool get isLoggedIn => true;
}

const blogForm =
    '<form id="ReplyForm" action="/blog/entry/42/new_reply"><input name="formhash" value="fixture-hash"><textarea name="content"></textarea></form>';
const pmForm =
    '<form id="pmForm" action="/pm/create.chii"><input name="formhash" value="fixture-hash"><input name="msg_receivers" value="2"><input name="msg_title" value="hello"><textarea name="msg_body"></textarea><input name="submit" value="发送"></form>';
void main() {
  test(
    'modern private conversation markup and message bodies are supported',
    () async {
      final inbox = RemotePrivateMessageRepository.parseList(
        '<div class="pm-conversation-scroll"><a class="pm-conversation-item" href="/pm/conversation/8.chii"><span class="pm-conversation-name">Fixture</span><span class="pm-conversation-desc">Summary</span><span class="pm-conversation-unread">2</span></a></div>',
        1,
      );
      expect(inbox.items.single.title, 'Fixture');
      expect(inbox.items.single.content, 'Summary');
      expect(inbox.items.single.unread, true);
      final api = ScopedApi(
        MockClient(
          (_) async => http.Response(
            '<div class="pm-chat-panel"><div class="pm-message-list"><div class="pm-message" id="msg_12"><a class="avatar" href="/user/fixture"></a><div class="pm-message-info"><small>2026</small></div><div class="pm-message-body">first<br>second</div></div></div></div>',
            200,
          ),
        ),
      );
      addTearDown(api.close);
      final messages = await RemotePrivateMessageRepository(
        api,
      ).thread('/pm/conversation/8.chii');
      expect(messages.single.id, 12);
      expect(messages.single.content, 'first\nsecond');
      expect(messages.single.sender, 'fixture');
    },
  );
  testWidgets(
    'unknown private delivery keeps draft and account switch clears it',
    (tester) async {
      final repo = DraftRepository();
      await tester.pumpWidget(
        host(PrivateMessageComposePage(repository: repo, recipient: '2')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Private test draft');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('发送'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(repo.calls, 1);
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .last
            .controller!
            .text,
        'Private test draft',
      );
      final button = tester.widget<FilledButton>(
        find.byWidgetPredicate((w) => w is FilledButton),
      );
      expect(button.onPressed, isNull);
      repo.changes.value = const SessionScope(
        username: 'other',
        accountId: 2,
        epoch: 2,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .last
            .controller!
            .text,
        isEmpty,
      );
      expect(repo.calls, 1);
    },
  );
  test(
    'system proxy keeps per-scheme and bypass rules without native callbacks',
    () {
      expect(
        windowsProxyDirective(
          Uri.parse('https://bgm.tv'),
          'http=127.0.0.1:80;https=127.0.0.1:7890',
          '',
        ),
        'PROXY 127.0.0.1:7890',
      );
      expect(
        windowsProxyDirective(
          Uri.parse('https://bgm.tv'),
          '127.0.0.1:7890',
          '*.bgm.tv;bgm.tv',
        ),
        'DIRECT',
      );
      expect(
        windowsProxyDirective(
          Uri.parse('http://intranet'),
          'proxy.test:80',
          '<local>',
        ),
        'DIRECT',
      );
      expect(
        () => windowsProxyDirective(
          Uri.parse('https://bgm.tv'),
          'user:pass@proxy.test:80',
          '',
        ),
        throwsA(isA<Exception>()),
      );
    },
  );
  test(
    'blog comment uses fresh site form, correct route and one confirmed POST',
    () async {
      final requests = <http.Request>[];
      final api = ScopedApi(
        MockClient((r) async {
          requests.add(r);
          return http.Response(
            r.method == 'GET' ? blogForm : '{"status":"ok"}',
            200,
          );
        }),
      );
      final repo = RemoteBangumiRepository(apiClient: api);
      addTearDown(repo.close);
      final target = ComposeCommentTarget.blog(42, 'blog');
      expect(target.key, startsWith('blog:'));
      expect(target.maxLength, 2000);
      await CommentSubmitUseCase(repo, target).call('hello');
      expect(requests.map((r) => r.method), ['GET', 'POST']);
      expect(requests.last.url.path, '/blog/entry/42/new_reply');
      expect(requests.last.bodyFields['formhash'], 'fixture-hash');
      expect(requests.last.bodyFields['content'], 'hello');
    },
  );
  test(
    'blog unknown result is not retried, changed scope never submits',
    () async {
      var posts = 0;
      final api = ScopedApi(
        MockClient((r) async {
          if (r.method == 'POST') posts++;
          return http.Response(r.method == 'GET' ? blogForm : '{}', 200);
        }),
      );
      final repo = RemoteBangumiRepository(apiClient: api);
      addTearDown(repo.close);
      await expectLater(
        CommentSubmitUseCase(
          repo,
          const ComposeCommentTarget.blog(42, ''),
        ).call('hello'),
        throwsA(
          isA<ApiException>().having((e) => e.outcomeUnknown, 'unknown', true),
        ),
      );
      expect(posts, 1);
      final useCase = CommentSubmitUseCase(
        repo,
        const ComposeCommentTarget.blog(42, ''),
      );
      api.active = const SessionScope(
        username: 'other',
        accountId: 2,
        epoch: 2,
      );
      await expectLater(
        useCase.call('private draft'),
        throwsA(isA<ApiException>()),
      );
      expect(posts, 1);
    },
  );
  test(
    'private inbox parses only local validated conversations and pagination',
    () {
      final page = RemotePrivateMessageRepository.parseList(
        '<form id="pmForm"><table><tr><td><a href="/pm/conversation/8.chii">Title</a><span class="pm_new"></span><span class="sub_title"><a href="/user/a">Sender</a></span><span class="tip">Preview</span></td></tr></table></form><a href="https://evil.test/pm/view/99.chii">evil</a><a href="?page=2">next</a>',
        1,
      );
      expect(page.items.length, 1);
      expect(page.items.single.id, 8);
      expect(page.items.single.unread, true);
      expect(page.hasMore, true);
      expect(
        () => RemotePrivateMessageRepository.parseList(
          '<html>verification</html>',
          1,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test(
    'private send reloads form and accepts only explicit confirmation',
    () async {
      final requests = <http.Request>[];
      var confirmed = true;
      final api = ScopedApi(
        MockClient((r) async {
          requests.add(r);
          return r.method == 'GET'
              ? http.Response(
                pmForm,
                200,
                headers: {'content-type': 'text/html; charset=utf-8'},
              )
              : confirmed
              ? http.Response('', 303, headers: {'location': '/pm/outbox.chii'})
              : http.Response('<html>unknown</html>', 200);
        }),
      );
      addTearDown(api.close);
      final repo = RemotePrivateMessageRepository(api);
      final form = await repo.form(recipient: '2');
      await repo.send(
        form,
        recipient: '2',
        title: 'Title',
        content: 'Private fixture',
      );
      expect(requests.map((r) => r.method), ['GET', 'GET', 'POST']);
      expect(requests.last.bodyFields['msg_body'], 'Private fixture');
      confirmed = false;
      await expectLater(
        repo.send(form, recipient: '2', title: 'Title', content: 'Fixture'),
        throwsA(
          isA<ApiException>().having((e) => e.outcomeUnknown, 'unknown', true),
        ),
      );
      api.active = const SessionScope(
        username: 'other',
        accountId: 2,
        epoch: 2,
      );
      final before = requests.length;
      await expectLater(
        repo.send(form, recipient: '2', title: 'Title', content: 'Fixture'),
        throwsA(isA<ApiException>()),
      );
      expect(requests.length, before);
    },
  );
  test(
    'private external form action and cross-origin redirects are rejected',
    () async {
      final api = ScopedApi(
        MockClient(
          (_) async => http.Response(
            pmForm.replaceFirst(
              '/pm/create.chii',
              'https://evil.test/pm/create.chii',
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(api.close);
      await expectLater(
        RemotePrivateMessageRepository(api).form(),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.siteDocument(
          'https://evil.test/pm/inbox.chii',
          scope: api.sessionScope,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test('comment orders are stable and preserve child hierarchy', () {
    CommunityReply r(int id, int time, int votes) => CommunityReply.fromJson({
      'id': id,
      'createdAt': time,
      'content': 'root',
      'user': {},
      'replies': [
        {'id': id + 100, 'content': 'child', 'user': {}},
      ],
      'reactions': [
        {'total': votes, 'value': 0, 'users': []},
      ],
    });
    final roots = [r(2, 200, 1), r(1, 100, 5), r(3, 300, 5)];
    expect(sortedComments(roots, CommentOrder.oldest).map((r) => r.id), [
      1,
      2,
      3,
    ]);
    expect(sortedComments(roots, CommentOrder.newest).map((r) => r.id), [
      3,
      2,
      1,
    ]);
    expect(sortedComments(roots, CommentOrder.likes).map((r) => r.id), [
      1,
      3,
      2,
    ]);
    expect(roots.first.id, 2);
    expect(
      sortedComments(roots, CommentOrder.likes).first.replies.single.id,
      101,
    );
  });
  testWidgets('episode details precede sortable comments', (tester) async {
    final repo = RemoteBangumiRepository(
      apiClient: ApiClient(
        client: MockClient(
          (r) async => http.Response(
            jsonEncode(
              r.url.path.endsWith('/comments')
                  ? [
                    {'id': 1, 'content': 'Comment fixture', 'user': {}},
                  ]
                  : {
                    'id': 5,
                    'name': 'Original title',
                    'nameCN': '章节标题',
                    'sort': 2,
                    'duration': '24m',
                    'airdate': '2026-10-01',
                    'desc': '章节简介',
                  },
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    );
    addTearDown(repo.close);
    await tester.pumpWidget(
      host(
        EpisodeCommentsPage(
          episode: SubjectEpisode.fromJson({'id': 5, 'sort': 2}),
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('章节标题'), findsOneWidget);
    expect(find.text('章节简介', findRichText: true), findsOneWidget);
    expect(find.text('最新'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('章节标题')).dy,
      lessThan(
        tester.getTopLeft(find.text('Comment fixture', findRichText: true)).dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('tag count has smaller distinct typography', (tester) async {
    await tester.pumpWidget(
      host(
        Scaffold(body: SubjectTagChip(name: '动画', count: 123, onTap: () {})),
      ),
    );
    final text = tester.widget<Text>(
      find.byWidgetPredicate((w) => w is Text && w.textSpan != null),
    );
    final spans = (text.textSpan as TextSpan).children!.cast<TextSpan>();
    expect(spans.last.style!.fontSize, lessThan(spans.first.style!.fontSize!));
    expect(spans.last.style!.color, isNot(spans.first.style!.color));
  });
  for (final index in [0, 7]) {
    testWidgets(
      'profile tab $index supports narrow large text without intrinsic layout',
      (tester) async {
        tester.view.physicalSize = const Size(390, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          host(
            UserProfilePage(
              username: 'fixture',
              repository: UserRepo(),
              initialIndex: index,
            ),
            scale: 1.8,
          ),
        );
        await tester.pumpAndSettle();
        if (index == 0) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -450));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final (tab, title, type) in [
    (3, 'User blog', BlogDetailPage),
    (4, 'User directory', IndexDetailPage),
  ]) {
    testWidgets('profile content $tab opens intended details', (tester) async {
      await tester.pumpWidget(
        host(
          UserProfilePage(
            username: 'fixture',
            repository: UserRepo(),
            initialIndex: tab,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.byType(type), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class DraftRepository implements PrivateMessageRepository {
  final changes = ValueNotifier(
    const SessionScope(username: 'fixture', accountId: 1, epoch: 1),
  );
  int calls = 0;
  @override
  SessionScope get scope => changes.value;
  @override
  Listenable get sessionChanges => changes;
  @override
  Future<ComposePrivateForm> form({
    String recipient = '',
    String? threadPath,
  }) async => ComposePrivateForm('/pm/compose.chii', '/pm/create.chii', {
    'formhash': 'fixture',
    'msg_receivers': '2',
  }, scope);
  @override
  Future<void> send(
    ComposePrivateForm form, {
    required String recipient,
    required String title,
    required String content,
  }) async {
    calls++;
    throw const ApiException('messageUnknown', outcomeUnknown: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UserRepo implements BangumiRepository, BlogRepository, IndexRepository {
  @override
  final Listenable collectionChanges = ChangeNotifier();
  @override
  bool get isLoggedIn => false;
  @override
  String get currentUsername => '';
  @override
  int effectiveSubjectCollectionCount(String username, int count) => count;
  @override
  Future<UserProfileData> fetchUserProfile(String username) async =>
      UserProfileData(
        user: CommunityUser.fromJson({
          'id': 1,
          'username': 'fixture',
          'nickname': 'Fixture',
          'stats': {
            'blog': 1234567,
            'friend': 123456,
            'subject': {
              '2': {'2': 1234567},
            },
          },
        }),
        timeline: [
          TimelineEntry.fromJson({
            'id': 1,
            'user': {'username': 'fixture'},
            'cat': 1,
            'memo': {'text': '[b]时间胶囊文字[/b] 长内容应该正确换行'},
            'createdAt': 1700000000,
          }),
        ],
        collections: [],
        characters: [],
        persons: [],
        blogs: [
          UserContentItem.fromBlog({'id': 42, 'title': 'User blog'}),
        ],
        indexes: [
          UserContentItem.fromIndex({'id': 5, 'title': 'User directory'}),
        ],
        friends: [],
      );
  @override
  Future<ComposeBlogDetail> fetchBlog(int id) async => ComposeBlogDetail(
    ComposeBlog.fromJson({
      'id': id,
      'title': 'User blog',
      'content': 'Body',
      'user': {},
    }),
    [],
    [],
  );
  @override
  Future<Map<String, dynamic>> indexInfo(int id) async => {
    'id': id,
    'title': 'User directory',
    'desc': 'Description',
  };
  @override
  Future<Paged<Map<String, dynamic>>> indexEntries(
    int id, {
    int offset = 0,
  }) async => Paged(items: [], offset: 0, limit: 30, total: 0);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
