import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/core/app_identity.dart';
import 'package:bangumi_flutter/core/auth/auth_service.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/network/cookie_session_client.dart';
import 'package:bangumi_flutter/core/network/platform_http_client.dart';
import 'package:bangumi_flutter/data/repositories/remote_account_settings_repository.dart';
import 'package:bangumi_flutter/data/repositories/remote_privacy_repository.dart';
import 'package:bangumi_flutter/data/repositories/web_privacy_form.dart';
import 'community_extensions_test.dart' show settingsHtml, session;
import 'privacy_and_image_regression_test.dart' show privacyHtml;

Future<MemorySecureVault> previousInstall() async {
  final vault = MemorySecureVault();
  await vault.write(
    'bangumi.auth.user.v1',
    jsonEncode({
      'id': 42,
      'username': 'tester',
      'nickname': 'Tester',
      'formHash': 'old',
    }),
  );
  await vault.write(
    'bangumi.auth.token.v1',
    jsonEncode({
      'access_token': 'fixture',
      'refresh_token': 'fixture-refresh',
      'expires_in': 3600,
      'saved_at': DateTime.now().millisecondsSinceEpoch,
    }),
  );
  final cookies = PersistentCookieStore(vault);
  await cookies.capture(
    Uri.parse('https://bgm.tv/login'),
    'chii_auth=fixture; Path=/; Secure; Max-Age=2592000, chii_sid=old; Path=/; Secure',
    userAgent: 'SavedBrowser/old-install',
  );
  return vault;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Android upgrade restores cookies, renews stale sid once and reads settings without login',
    () async {
      final vault = await previousInstall();
      final store = PersistentCookieStore(vault);
      await store.initialize();
      const channel = MethodChannel('com.xiaoyv.bangumi/network');
      var requests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'cancelRequest') return null;
            final args = call.arguments as Map;
            expect(args['method'], 'GET');
            expect(args['url'], 'https://bgm.tv/settings');
            final headers = args['headers'] as Map;
            expect(headers['user-agent'], 'SavedBrowser/old-install');
            expect(headers['cookie'], contains('chii_auth=fixture'));
            requests++;
            if (requests == 1) {
              return {
                'statusCode': 200,
                'headers': {'set-cookie': 'chii_sid=renewed; Path=/; Secure'},
                'body': Uint8List.fromList(
                  utf8.encode('<div class="guest">Session renewed</div>'),
                ),
              };
            }
            expect(headers['cookie'], contains('chii_sid=renewed'));
            return {
              'statusCode': 200,
              'headers': <String, String>{},
              'body': Uint8List.fromList(utf8.encode(settingsHtml())),
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final client = CookieSessionClient(AndroidBangumiHttpClient(), store);
      final auth = AuthService(client: client, cookies: store, vault: vault);
      await auth.initialize();
      final api = ApiClient(client: client, authService: auth);
      addTearDown(api.close);
      addTearDown(auth.dispose);
      final result =
          await RemoteAccountSettingsRepository(api, onChanged: () {}).load();
      expect(result.value('nickname'), 'Tester');
      expect(requests, 2);
      expect(auth.isLoggedIn, true);
      final restored = PersistentCookieStore(vault);
      await restored.initialize();
      expect(
        restored.headerFor(Uri.parse('https://bgm.tv/settings')),
        contains('chii_sid=renewed'),
      );
      expect(
        restored.authenticationUserAgent(Uri.parse('https://bgm.tv/settings')),
        'SavedBrowser/old-install',
      );
    },
  );

  test(
    'fresh web nonce and untouched settings survive submit and a second process restore',
    () async {
      final vault = await previousInstall();
      final saved = {'timelineReply': 'friends'};
      var posts = 0, reads = 0;
      Future<(ApiClient, AuthService)> restart() async {
        final store = PersistentCookieStore(vault);
        await store.initialize();
        final client = CookieSessionClient(
          MockClient((request) async {
            expect(request.url.path, '/settings/privacy');
            if (request.method == 'POST') {
              posts++;
              expect(request.followRedirects, false);
              expect(request.bodyFields['formhash'], 'nonce-$reads');
              expect(request.bodyFields['privacy_set[30]'], '1');
              expect(request.bodyFields['privacy_set[32]'], '2');
              expect(request.bodyFields.keys, isNot(contains('submit_ignore')));
              saved['timelineCollectReply'] = 'none';
              return http.Response(
                '',
                303,
                headers: {'location': '/settings/privacy'},
              );
            }
            reads++;
            return http.Response(
              privacyHtml({
                'timelineReply': 'friends',
                if (posts > 0) 'timelineCollectReply': 'none',
              }, 'nonce-$reads'),
              200,
            );
          }),
          store,
        );
        final auth = AuthService(client: client, cookies: store, vault: vault);
        await auth.initialize();
        final api = ApiClient(client: client, authService: auth);
        addTearDown(api.close);
        addTearDown(auth.dispose);
        return (api, auth);
      }

      final (api, _) = await restart();
      final repo = RemotePrivacyRepository(api);
      final old = await repo.load();
      await repo.save(old, {'timelineCollectReply': 'none'});
      final (again, _) = await restart();
      final restored = await RemotePrivacyRepository(again).load();
      expect(restored.settings, {...old.settings, ...saved});
      expect(posts, 1);
    },
  );

  test(
    'web parser rejects another identity, missing nonce and invalid audience',
    () {
      for (final source in [
        privacyHtml().replaceAll('/user/tester', '/user/another'),
        privacyHtml({}, ''),
        privacyHtml().replaceFirst('value="0" selected', 'value="9" selected'),
        privacyHtml().replaceAll(
          'action="/settings/privacy"',
          'action="https://foreign.example/save"',
        ),
      ]) {
        expect(
          () => parseWebPrivacy(source, session),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );

  test(
    'one damaged historical cookie does not erase valid authentication',
    () async {
      final vault = await previousInstall();
      final source =
          jsonDecode((await vault.read('bangumi.cookies.v1'))!) as List;
      source.insert(0, {
        'name': 'broken',
        'expiresAt': {'bad': true},
      });
      await vault.write('bangumi.cookies.v1', jsonEncode(source));
      final store = PersistentCookieStore(vault);
      await store.initialize();
      expect(
        store.headerFor(Uri.parse('https://bgm.tv/settings')),
        contains('chii_auth=fixture'),
      );
      expect(await vault.read('bangumi.cookies.v1'), contains('broken'));
      // 不延长服务器有效期，也不能在退出或服务器删 Cookie 后复活会话。
      await store.capture(
        Uri.parse('https://bgm.tv/'),
        'chii_auth=; Path=/; Secure; Max-Age=0',
      );
      expect(
        store.headerFor(Uri.parse('https://bgm.tv/')),
        isNot(contains('chii_auth=')),
      );
      expect(browserUserAgent, isNot(contains('BangumiFlutter/$appVersion')));
    },
  );

  test(
    'server-expired web login is not resurrected and does not sign out OAuth',
    () async {
      final vault = await previousInstall();
      final store = PersistentCookieStore(vault);
      await store.initialize();
      var calls = 0;
      final client = CookieSessionClient(
        MockClient((_) async {
          calls++;
          return http.Response(
            '<form id="loginForm"></form>',
            200,
            headers: {'set-cookie': 'chii_auth=; Path=/; Secure; Max-Age=0'},
          );
        }),
        store,
      );
      final auth = AuthService(client: client, cookies: store, vault: vault);
      await auth.initialize();
      final api = ApiClient(client: client, authService: auth);
      addTearDown(api.close);
      addTearDown(auth.dispose);
      await expectLater(
        api.accountSettings(scope: api.sessionScope),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'profileWebLoginRequired',
          ),
        ),
      );
      expect(calls, 1);
      expect(auth.isLoggedIn, true);
      expect(await vault.read('bangumi.auth.token.v1'), isNotNull);
      await vault.write('bangumi.cookies.v1', '{damaged');
      await PersistentCookieStore(vault).initialize();
      expect(await vault.read('bangumi.cookies.v1'), '{damaged');
    },
  );
}
