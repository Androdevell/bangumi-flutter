import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bangumi_flutter/app/state/session_scope.dart';
import 'package:bangumi_flutter/core/auth/auth_service.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/network/cookie_session_client.dart';
import 'package:bangumi_flutter/core/network/safe_image_file_service.dart';
import 'package:bangumi_flutter/core/media/rich_image_policy.dart';
import 'package:bangumi_flutter/core/media/avatar_revision.dart';
import 'package:bangumi_flutter/core/text/emoji_catalog.dart';
import 'package:bangumi_flutter/core/text/bbcode_document.dart';
import 'package:bangumi_flutter/core/community_models.dart';
import 'package:bangumi_flutter/core/subject_detail_models.dart';
import 'package:bangumi_flutter/core/paged.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/data/repositories/remote_account_settings_repository.dart';
import 'package:bangumi_flutter/data/repositories/remote_group_repository.dart';
import 'package:bangumi_flutter/data/repositories/remote_episode_progress_repository.dart';
import 'package:bangumi_flutter/domain/models/account_settings.dart';
import 'package:bangumi_flutter/domain/models/group_models.dart';
import 'package:bangumi_flutter/domain/repositories/account_settings_repository.dart';
import 'package:bangumi_flutter/domain/repositories/episode_progress_repository.dart';
import 'package:bangumi_flutter/domain/repositories/group_repository.dart';
import 'package:bangumi_flutter/domain/use_cases/comment_submit_use_case.dart';
import 'package:bangumi_flutter/features/community/comment_composer_controller.dart';
import 'package:bangumi_flutter/features/community/community_widgets.dart';
import 'package:bangumi_flutter/features/subject/episode_progress_controller.dart';
import 'package:bangumi_flutter/features/groups/group_controller.dart';
import 'package:bangumi_flutter/features/profile/editor/profile_editor_controller.dart';
import 'package:bangumi_flutter/features/profile/editor/profile_editor_page.dart';
import 'package:bangumi_flutter/widgets/bangumi_rich_text.dart';
import 'package:bangumi_flutter/widgets/emoji_picker.dart';
import 'package:bangumi_flutter/widgets/episode_progress_panel.dart';
import 'comment_experience_test.dart' show host;

const session = SessionScope(username: 'tester', accountId: 42, epoch: 0);
String settingsHtml({
  String nickname = 'Tester',
  String bio = 'Introduction',
  String formhash = 'fresh',
  String timezone = '8',
}) => '''
<form action="/settings" method="post" enctype="multipart/form-data">
<input type="hidden" name="formhash" value="$formhash"><input type="hidden" name="keep" value="untouched">
<input name="nickname" value="$nickname" maxlength="32"><input name="sign_input" value="signature">
<table><tr><td>Avatar</td><td><img src="//lain.bgm.tv/avatar.jpg"><input name="picfile" type="file"></td></tr></table>
<span>http://<input name="newsite" value="example.com"></span><textarea name="newbio">$bio</textarea>
<select name="timeoffsetnew"><option value="0" ${timezone == '0' ? 'selected' : ''}>UTC</option><option value="8" ${timezone == '8' ? 'selected' : ''}>UTC+8</option></select>
<label>受限内容 <input type="checkbox" name="show_restricted" value="1"></label>
<input type="checkbox" name="keep_checked" value="yes" checked><input name="submit" type="submit" value="save">
</form><form><input type="password" name="password"><input name="email" value="private@example.test"></form>''';
CommunityReply comment(
  int id, {
  int state = 0,
  List<Map<String, dynamic>> replies = const [],
}) => CommunityReply.fromJson({
  'id': id,
  'state': state,
  'content': 'body $id',
  'creatorID': id + 100,
  'creator': {'id': id + 100, 'username': 'u$id', 'nickname': 'User $id'},
  'replies': replies,
});
const imageUrl = 'https://lsky.ry.mk/i/2026/10/14/03d6f48a4f95c.webp';
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6R84AAAAASUVORK5CYII=',
);

Future<(ApiClient, AuthService)> authenticated(http.Client client) async {
  final vault = MemorySecureVault();
  await vault.write(
    'bangumi.auth.user.v1',
    jsonEncode({
      'id': 42,
      'username': 'tester',
      'nickname': 'Tester',
      'formHash': 'csrf',
    }),
  );
  await vault.write(
    'bangumi.auth.token.v1',
    jsonEncode({
      'access_token': 'synthetic',
      'refresh_token': 'synthetic-refresh',
      'expires_in': 3600,
      'saved_at': DateTime.now().millisecondsSinceEpoch,
    }),
  );
  final cookies = PersistentCookieStore(vault);
  await cookies.initialize();
  await cookies.capture(
    Uri.parse('https://bgm.tv/'),
    'chii_auth=synthetic-cookie; Path=/; Secure',
  );
  final transport = CookieSessionClient(client, cookies);
  final auth = AuthService(
    client: transport,
    cookies: cookies,
    vault: vault,
    appId: 'fixture-app',
    appSecret: 'fixture-secret',
  );
  await auth.initialize();
  return (ApiClient(client: transport, authService: auth), auth);
}

void main() {
  test('avatar revisions affect only the chosen avatar and stay canonical', () {
    const avatar = 'https://lain.bgm.tv/test-profile-avatar.png';
    const other = 'https://lain.bgm.tv/other-profile-avatar.png';
    AvatarRevision.bump(avatar);
    final first = AvatarRevision.resolve(avatar);
    expect(first, contains('_client_avatar='));
    expect(AvatarRevision.resolve(first), first);
    expect(AvatarRevision.resolve(other), other);
    AvatarRevision.bump(first);
    expect(AvatarRevision.resolve(avatar), isNot(first));
    expect(
      AvatarRevision.resolve('https://example.com/avatar.png'),
      'https://example.com/avatar.png',
    );
  });
  test(
    'group detail discards old account results and keeps independent errors',
    () async {
      final repo = _GroupDetail();
      final model = GroupDetailController(repo, 'test');
      final previous = model.refresh();
      repo.changes.notifyListeners();
      repo.details[0].complete(_group('old account'));
      repo.pages[0].complete(
        Paged(items: const <Topic>[], offset: 0, limit: 20),
      );
      await previous;
      expect(model.state.group, isNull);
      repo.details[1].complete(_group('new account'));
      repo.pages[1].completeError(const ApiException('topics unavailable'));
      await Future<void>.delayed(Duration.zero);
      expect(model.state.group!.title, 'new account');
      expect(model.state.error, isNotNull);
      expect(model.state.detailError, isNull);
      expect(model.state.loading, isFalse);
      model.dispose();
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async => RichImagePolicy.instance.initialize(MemorySecureVault()));
  test(
    'all six catalogs contain unique exact mappings and valid three-digit stickers',
    () {
      expect(EmojiCatalog.entries.length, 429);
      expect(EmojiCatalog.entries.map((e) => e.code).toSet().length, 429);
      expect(
        EmojiCatalog.entries.map((e) => e.family).toSet(),
        EmojiCatalog.families.toSet(),
      );
      for (final item in EmojiCatalog.entries) {
        expect(bangumiEmojiUrl(item.code), item.url);
        expect(Uri.parse(item.url).host, 'lain.bgm.tv');
      }
      expect(bangumiEmojiUrl('musume_118'), endsWith('musume_118.gif'));
      expect(bangumiEmojiUrl('musume_999'), isNull);
      expect(bangumiEmojiUrl('bmo1'), isNull);
      expect(bangumiEmojiUrl('bgm124_tv'), endsWith('101.gif'));
    },
  );
  test('sized WebP BBCode and adjacent source URLs stay intact', () {
    final doc = BangumiBbCode.parse(
      '[img=224,126]$imageUrl[/img][img]https://lain.bgm.tv/b.jpg[/img]',
    );
    expect(doc.nodes.where((n) => n.tag == 'img').length, 2);
    expect(BangumiBbCode.plain(doc.nodes.first.children), imageUrl);
  });
  test(
    'image preferences persist allow-list and most-recent unique emoji codes',
    () async {
      final vault = MemorySecureVault();
      final policy = RichImagePolicy();
      await policy.initialize(vault);
      expect(policy.allows(Uri.parse(imageUrl)), isFalse);
      await policy.allowHost('lsky.ry.mk');
      expect(policy.allows(Uri.parse(imageUrl)), isTrue);
      await policy.rememberEmoji('blake_118');
      await policy.rememberEmoji('bgm38');
      await policy.rememberEmoji('blake_118');
      final restored = RichImagePolicy();
      await restored.initialize(vault);
      expect(restored.recentEmojis, ['blake_118', 'bgm38']);
      await restored.setMode(ExternalImageMode.blocked);
      expect(restored.allows(Uri.parse(imageUrl)), isFalse);
      expect(restored.allows(Uri.parse('https://lain.bgm.tv/a.jpg')), isTrue);
    },
  );
  for (final url in [
    'http://example.com/a',
    'https://127.0.0.1/a',
    'https://10.0.0.1/a',
    'https://169.254.1.1/a',
    'https://100.64.0.1/a',
    'https://localhost/a',
    'https://a.local/a',
    'https://user:secret@example.com/a',
    'https://example.com:8443/a',
    'https://[::1]/a',
  ]) {
    test(
      'rejects unsafe image $url',
      () => expect(ImageUrlSafety.valid(Uri.parse(url)), isFalse),
    );
  }
  test(
    'safe image transport strips credentials and validates redirects',
    () async {
      final requests = <http.Request>[];
      final service = SafeImageFileService(
        MockClient((request) async {
          requests.add(request);
          return requests.length == 1
              ? http.Response(
                '',
                302,
                headers: {'location': 'https://cdn.example.net/final.png'},
              )
              : http.Response.bytes(
                png,
                200,
                headers: {'content-type': 'image/png'},
              );
        }),
        lookup: (_) async => [InternetAddress('93.184.216.34')],
      );
      final response = await service.get(
        'https://example.org/start',
        headers: {
          'cookie': 'private',
          'authorization': 'Bearer private',
          'referer': 'private',
          'if-none-match': 'etag',
        },
      );
      expect(requests.length, 2);
      for (final request in requests) {
        expect(request.followRedirects, isFalse);
        expect(request.headers['cookie'], isNull);
        expect(request.headers['authorization'], isNull);
        expect(request.headers['referer'], isNull);
      }
      expect(await response.content.expand((c) => c).toList(), png);
    },
  );
  test(
    'redirect to private DNS is stopped before sending credentials or network request',
    () async {
      var calls = 0;
      final service = SafeImageFileService(
        MockClient((_) async {
          calls++;
          return http.Response(
            '',
            302,
            headers: {'location': 'https://internal.test/a'},
          );
        }),
        lookup:
            (host) async => [
              InternetAddress(
                host == 'internal.test' ? '192.168.1.1' : '93.184.216.34',
              ),
            ],
      );
      await expectLater(
        service.get('https://example.org/a'),
        throwsA(isA<HttpException>()),
      );
      expect(calls, 1);
    },
  );
  test('image byte budget rejects oversized response', () async {
    final service = SafeImageFileService(
      MockClient.streaming(
        (_, __) async => http.StreamedResponse(
          const Stream.empty(),
          200,
          contentLength: SafeImageFileService.maxBytes + 1,
        ),
      ),
      lookup: (_) async => [InternetAddress('93.184.216.34')],
    );
    await expectLater(
      service.get('https://example.org/a'),
      throwsA(isA<HttpException>()),
    );
  });
  testWidgets('external image offers in-app load instead of raw BBCode', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Scaffold(body: BangumiRichText('[img=224,126]$imageUrl[/img]')),
      ),
    );
    expect(find.text('加载图片'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
    await tester.tap(find.text('加载图片'));
    await tester.pump();
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.textContaining('[img='), findsNothing);
  });
  testWidgets('complete emoji selector inserts a three-digit sticker', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () => showEmojiPicker(context),
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('娘'));
    await tester.pump();
    expect(find.byTooltip('(musume_01)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'unavailable root retains visible children while hiding old text',
    () async {
      final api = ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {
                'id': 1,
                'state': 6,
                'content': 'hidden',
                'replies': [
                  {'id': 2, 'content': '[img]$imageUrl[/img]'},
                ],
              },
            ]),
            200,
          ),
        ),
      );
      final repo = RemoteBangumiRepository(apiClient: api);
      final replies = await repo.fetchEpisodeComments(1737853);
      expect(replies.single.content, isEmpty);
      expect(replies.single.replies.single.content, contains(imageUrl));
      repo.close();
    },
  );
  testWidgets('nested reply buttons target child and root separately', (
    tester,
  ) async {
    final root = comment(
      1,
      replies: [
        {
          'id': 2,
          'content': 'child',
          'creatorID': 102,
          'creator': {'id': 102, 'username': 'u2', 'nickname': 'User 2'},
        },
      ],
    );
    (int, int)? target;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: CommunityReplyList(
            items: [root],
            currentUsername: 'tester',
            onUserTap: (_) {},
            onLike: (_, __) async {},
            onReply: (r, child) => target = (r.id, child.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('回复').first);
    expect(target, (1, 2));
    await tester.tap(find.byTooltip('回复').last);
    expect(target, (1, 1));
    expect(find.byTooltip('贴贴'), findsNWidgets(2));
  });
  testWidgets('deep replies remain visible without unbounded indentation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic> nested = {'id': 8, 'content': 'deepest visible'};
    for (var id = 7; id >= 2; id--) {
      nested = {
        'id': id,
        'content': 'level $id',
        'replies': [nested],
      };
    }
    await tester.pumpWidget(
      host(
        Scaffold(
          body: CommunityReplyList(
            items: [
              comment(1, replies: [nested]),
            ],
            currentUsername: 'tester',
            onUserTap: (_) {},
            onLike: (_, __) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('展开更多回复'));
    await tester.tap(find.text('展开更多回复'));
    await tester.pumpAndSettle();
    expect(find.text('deepest visible', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('episode menu cannot write into a newly switched account', (
    tester,
  ) async {
    final repo = _Progress();
    final model = EpisodeProgressController(repo, 1);
    await model.refresh();
    await tester.pumpWidget(
      host(
        Scaffold(
          body: EpisodeProgressPanel(
            controller: model,
            repository: _LoggedInView(),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    repo.current = const SessionScope(
      username: 'other',
      accountId: 99,
      epoch: 1,
    );
    repo.changes.notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.text('只标记本集 · 看过'));
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
  test(
    'nested publishing uses root relation and child recipient; does not retry',
    () async {
      var posts = 0;
      final (api, auth) = await authenticated(
        MockClient((request) async {
          posts++;
          expect(request.url.path, '/subject/ep/1737853/new_reply');
          expect(request.bodyFields['related'], '1');
          expect(request.bodyFields['sub_reply_uid'], '102');
          expect(request.bodyFields['post_uid'], '101');
          expect(request.bodyFields['content'], 'reply');
          return http.Response('{"status":"ok"}', 200);
        }),
      );
      final repo = RemoteBangumiRepository(apiClient: api);
      final target = ComposeCommentTarget.reply(
        const ComposeCommentTarget.episode(1737853, 'Episode'),
        ComposeCommentReplyTarget(root: comment(1), reply: comment(2)),
      );
      await CommentSubmitUseCase(repo, target).call('reply');
      expect(posts, 1);
      expect(target.key, contains(':1:2'));
      repo.close();
      auth.dispose();
    },
  );
  test('session invalidation permanently disables old comment editor', () {
    final editor = CommentComposerController(
      maxLength: 1000,
      submit: (_) async {},
      isCurrent: () => false,
    );
    editor.dispatch(EditComment(const TextEditingValue(text: 'draft')));
    editor.invalidateSession();
    expect(editor.canSubmit, isFalse);
    expect(editor.state.status, CommentSubmitStatus.stale);
    editor.dispose();
  });
  test(
    'episode parses individual collection rather than inferring from aggregate count',
    () {
      final e = SubjectEpisode.fromJson({
        'id': 3,
        'subjectID': 8,
        'type': 1,
        'disc': 2,
        'sort': 2.5,
        'collection': {'status': 3, 'updatedAt': 1780000000},
      });
      expect(e.collectionStatus, 3);
      expect(e.collectionUpdatedAt, isNotNull);
      expect(e.sort, 2.5);
      expect(e.type, 1);
      expect(e.disc, 2);
    },
  );
  test('progress drops late account result', () async {
    final repo = _Progress();
    final completer = Completer<Paged<SubjectEpisode>>();
    repo.pending = completer.future;
    final controller = EpisodeProgressController(repo, 8);
    final first = controller.refresh();
    repo.pending = Future.value(Paged(items: const [], offset: 0, limit: 40));
    repo.current = const SessionScope(
      username: 'other',
      accountId: 2,
      epoch: 1,
    );
    repo.changes.notifyListeners();
    completer.complete(
      Paged(
        items: [
          SubjectEpisode.fromJson({'id': 999, 'sort': 1}),
        ],
        offset: 0,
        limit: 40,
      ),
    );
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.page!.items, isEmpty);
    controller.dispose();
  });
  test(
    'confirmed episode update retains saved state if refresh fails',
    () async {
      final repo = _Progress();
      final model = EpisodeProgressController(repo, 8);
      await model.refresh();
      repo.failReads = true;
      await model.save(SubjectEpisode.fromJson({'id': 1}), 2);
      expect(repo.batch, isFalse);
      expect(model.state.saved, isTrue);
      expect(model.state.error, isNotNull);
      model.dispose();
    },
  );
  test(
    'progress write invalidates only related resources and keeps explicit batch',
    () async {
      final (api, auth) = await authenticated(
        MockClient((request) async {
          if (request.method == 'PATCH') {
            expect(jsonDecode(request.body), {'type': 2, 'batch': false});
            return http.Response('', 204);
          }
          return http.Response('[]', 200);
        }),
      );
      final repo = RemoteEpisodeProgressRepository(api, onChanged: () {});
      await repo.save(8, 3, 2, session: api.sessionScope);
      api.close();
      auth.dispose();
    },
  );
  test(
    'group lists pass validated remote mode/sort/pagination and stamp topic type',
    () async {
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/topics')) {
            return http.Response(
              '{"data":[{"id":7,"title":"thread"}],"total":1}',
              200,
            );
          }
          expect(request.url.queryParameters, {
            'mode': 'all',
            'sort': 'updated',
            'offset': '20',
            'limit': '20',
          });
          return http.Response(
            '{"data":[{"name":"test","title":"Test","members":4}],"total":21}',
            200,
          );
        }),
      );
      final groups = RemoteGroupRepository(api);
      final page = await groups.list(offset: 20);
      expect(page.items.single.name, 'test');
      expect(page.hasMore, isFalse);
      expect((await groups.topics('test')).items.single.type, 'group');
      await expectLater(
        groups.list(mode: 'joined'),
        throwsA(isA<ApiException>()),
      );
      api.close();
    },
  );
  test(
    'group selection keeps cached listing and isolates account reset',
    () async {
      final groups = _Groups();
      final model = GroupDirectoryController(groups);
      await model.load();
      model.select(sort: 'members');
      await Future<void>.delayed(Duration.zero);
      model.select(sort: 'updated');
      expect(model.state.items.single.title, 'updated');
      expect(groups.calls, 2);
      groups.changes.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(groups.calls, 3);
      model.dispose();
    },
  );
  test(
    'profile parser preserves originals and only actual checkbox values',
    () {
      final form = parseAccountSettings(
        settingsHtml(bio: '[b]Hello &amp; world[/b]'),
        session,
      );
      expect(form.value('newbio'), '[b]Hello & world[/b]');
      expect(form.avatarUrl, 'https://lain.bgm.tv/avatar.jpg');
      expect(form.value('keep'), 'untouched');
      expect(form.fields.containsKey('show_restricted'), isFalse);
      expect(form.checkboxValues['show_restricted'], '1');
      expect(form.restrictedField, 'show_restricted');
      expect(form.value('keep_checked'), 'yes');
      expect(form.fields.containsKey('password'), isFalse);
      expect(form.fields.containsKey('email'), isFalse);
      expect(form.sitePrefix, 'http://');
      expect(form.timezones, {'0': 'UTC', '8': 'UTC+8'});
    },
  );
  for (final invalid in [
    '<form id="loginForm"></form>',
    '<form><input name="nickname" value="x"></form>',
  ]) {
    test(
      'incomplete settings form cannot become a blank writable profile',
      () => expect(
        () => parseAccountSettings(invalid, session),
        throwsA(isA<ApiException>()),
      ),
    );
  }
  test(
    'profile adapter posts multipart, reads back values and leaves unrelated fields intact',
    () async {
      var serverNickname = 'Tester';
      var posts = 0;
      final (api, auth) = await authenticated(
        MockClient((request) async {
          expect(request.url.toString(), 'https://bgm.tv/settings');
          expect(request.followRedirects, isFalse);
          expect(request.headers['authorization'], isNull);
          if (request.method == 'POST') {
            posts++;
            expect(
              request.headers['content-type'],
              startsWith('multipart/form-data'),
            );
            expect(request.body, contains('name="nickname"\r\n\r\nNew name'));
            expect(request.body, contains('name="keep"\r\n\r\nuntouched'));
            expect(request.body, isNot(contains('name="show_restricted"')));
            expect(request.body, isNot(contains('name="password"')));
            serverNickname = 'New name';
            return http.Response('', 303, headers: {'location': '/settings'});
          }
          return http.Response.bytes(
            utf8.encode(settingsHtml(nickname: serverNickname)),
            200,
          );
        }),
      );
      final repo = RemoteAccountSettingsRepository(api, onChanged: () {});
      final original = await repo.load();
      final confirmed = await repo.save(original, {'nickname': 'New name'});
      expect(confirmed.value('nickname'), 'New name');
      expect(auth.user!.nickname, 'New name');
      expect(posts, 1);
      api.close();
      auth.dispose();
    },
  );
  test(
    'profile unknown outcome locks retry until successful fresh read',
    () async {
      final repo = _Settings();
      final model = ProfileEditorController(repo);
      await model.load();
      repo.failSave = true;
      expect(await model.save({'nickname': 'New'}), isFalse);
      expect(model.state.unknown, isTrue);
      await model.save({'nickname': 'New'});
      expect(repo.saves, 1);
      repo.failLoad = true;
      await model.load();
      expect(model.state.unknown, isTrue);
      repo.failLoad = false;
      await model.load();
      expect(model.state.unknown, isFalse);
      model.dispose();
    },
  );
  test('switching account makes profile editor stale', () async {
    final repo = _Settings();
    final model = ProfileEditorController(repo);
    await model.load();
    repo.currentScope = const SessionScope(
      username: 'other',
      accountId: 99,
      epoch: 2,
    );
    repo.changes.notifyListeners();
    expect(model.state.stale, isTrue);
    expect(await model.save({'nickname': 'Other'}), isFalse);
    expect(repo.saves, 0);
    model.dispose();
  });
  test(
    'same account revalidation can reload and save without closing the editor',
    () async {
      final repo = _Settings();
      final model = ProfileEditorController(repo);
      await model.load();
      repo.currentScope = SessionScope(
        username: session.username,
        accountId: session.accountId,
        epoch: session.epoch + 1,
      );
      repo.changes.notifyListeners();
      expect(model.state.stale, false);
      expect(await model.save({'nickname': 'New'}), false);
      await model.load();
      expect(await model.save({'nickname': 'New'}), true);
      model.dispose();
    },
  );
  for (final locale in ['zh', 'en', 'ja']) {
    testWidgets(
      'profile editor keeps fields and fits narrow large text in $locale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = _Settings();
        await tester.pumpWidget(
          host(ProfileEditorPage(repository: repo), locale: locale, scale: 2),
        );
        await tester.pumpAndSettle();
        final name = find.byType(TextFormField).first;
        await tester.enterText(name, 'Changed');
        await tester.pump();
        expect(tester.widget<TextFormField>(name).controller!.text, 'Changed');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

class _Progress implements EpisodeProgressRepository {
  int saves = 0;
  final changes = ChangeNotifier();
  SessionScope current = session;
  Future<Paged<SubjectEpisode>>? pending;
  bool failReads = false, batch = false;
  @override
  SessionScope get scope => current;
  @override
  Listenable get sessionChanges => changes;
  @override
  Future<Paged<SubjectEpisode>> load(
    int subjectId, {
    int offset = 0,
    bool fresh = false,
  }) async {
    if (failReads) throw const ApiException('read failed');
    return pending ??
        Paged(
          items: [
            SubjectEpisode.fromJson({'id': 1, 'sort': 1}),
          ],
          offset: offset,
          limit: 40,
        );
  }

  @override
  Future<void> save(
    int subjectId,
    int episodeId,
    int status, {
    required SessionScope session,
    bool batch = false,
  }) async {
    saves++;
    this.batch = batch;
  }
}

class _LoggedInView implements BangumiRepository {
  @override
  bool get isLoggedIn => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Groups implements GroupRepository {
  final changes = ChangeNotifier();
  int calls = 0;
  @override
  Listenable get sessionChanges => changes;
  @override
  bool get isLoggedIn => false;
  @override
  Future<Paged<ComposeGroup>> list({
    String mode = 'all',
    String sort = 'updated',
    int offset = 0,
    bool fresh = false,
  }) async {
    calls++;
    return Paged(
      items: [
        ComposeGroup(
          name: 'test',
          title: sort,
          description: '',
          icon: '',
          members: 1,
          topics: 1,
        ),
      ],
      offset: offset,
      limit: 20,
    );
  }

  @override
  Future<ComposeGroup> detail(String name) => throw UnimplementedError();
  @override
  Future<Paged<Topic>> topics(
    String name, {
    int offset = 0,
    bool fresh = false,
  }) => throw UnimplementedError();
}

ComposeGroup _group(String title) => ComposeGroup(
  name: 'test',
  title: title,
  description: '',
  icon: '',
  members: 1,
  topics: 1,
);

class _GroupDetail extends _Groups {
  final details = <Completer<ComposeGroup>>[];
  final pages = <Completer<Paged<Topic>>>[];
  @override
  Future<ComposeGroup> detail(String name) {
    final result = Completer<ComposeGroup>();
    details.add(result);
    return result.future;
  }

  @override
  Future<Paged<Topic>> topics(
    String name, {
    int offset = 0,
    bool fresh = false,
  }) {
    final result = Completer<Paged<Topic>>();
    pages.add(result);
    return result.future;
  }
}

class _Settings implements AccountSettingsRepository {
  SessionScope currentScope = session;
  final changes = ChangeNotifier();
  bool failSave = false, failLoad = false;
  int saves = 0;
  @override
  SessionScope get scope => currentScope;
  @override
  Listenable get sessionChanges => changes;
  @override
  Future<ComposeAccountSettings> load() async {
    if (failLoad) throw const ApiException('read failed');
    return parseAccountSettings(settingsHtml(), scope);
  }

  @override
  Future<ComposeAccountSettings> save(
    ComposeAccountSettings original,
    Map<String, String> edits, {
    Uint8List? avatar,
  }) async {
    saves++;
    if (failSave) {
      throw const ApiException('profileUnconfirmed', outcomeUnknown: true);
    }
    return parseAccountSettings(
      settingsHtml(nickname: edits['nickname'] ?? 'Tester'),
      scope,
    );
  }
}
