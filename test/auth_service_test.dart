import 'dart:convert';

import 'package:bangumi_flutter/core/auth/auth_service.dart';
import 'package:bangumi_flutter/core/auth/auth_models.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/network/cookie_session_client.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('completes captcha web login and OAuth exchange', () async {
    final vault = MemorySecureVault();
    final cookies = PersistentCookieStore(vault);
    await cookies.initialize();
    final rawClient = MockClient((request) async {
      switch (request.url.path) {
        case '/login':
          return http.Response(
            '<form id="loginForm">'
            '<input name="referer" value="https://bgm.tv/">'
            '<input name="dreferer" value="https://bgm.tv/">'
            '<input name="once" value="nonce">'
            '</form>',
            200,
            headers: {'set-cookie': 'login_session=one; Path=/; Secure'},
          );
        case '/signup/captcha':
          expect(request.headers['cookie'], contains('login_session=one'));
          return http.Response.bytes([1, 2, 3], 200);
        case '/FollowTheRabbit':
          final form = request.bodyFields;
          expect(form['once'], 'nonce');
          expect(form['email'], 'user@example.com');
          if (form['captcha_challenge_field'] == 'wrong') {
            return http.Response.bytes(
              utf8.encode(
                '<div id="colunmNotice"><div class="text">验证码输入错误</div></div>',
              ),
              200,
              headers: {'content-type': 'text/html'},
            );
          }
          expect(form['captcha_challenge_field'], '1234');
          return http.Response(
            '<main id="main"><div id="header"><h1>测试用户</h1></div></main>'
            '<div class="idBadgerNeue"><a class="avatar" href="/user/tester">'
            '<span style="background-image:url(//lain.bgm.tv/avatar.jpg)"></span>'
            '</a></div><input name="formhash" value="form-token">',
            200,
            headers: {
              'set-cookie': 'chii_auth=signed-in; Path=/; Secure',
              'content-type': 'text/html; charset=utf-8',
            },
          );
        case '/oauth/authorize':
          expect(request.followRedirects, isFalse);
          expect(request.headers['cookie'], contains('chii_auth=signed-in'));
          expect(request.url.queryParameters['client_id'], isNotEmpty);
          expect(request.bodyFields['client_id'], isNotEmpty);
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  Uri.parse('http://localhost/callback')
                      .replace(
                        queryParameters: {
                          'code': 'oauth-code',
                          'state': request.url.queryParameters['state']!,
                        },
                      )
                      .toString(),
            },
          );
        case '/oauth/access_token':
          expect(request.bodyFields['client_id'], isNotEmpty);
          expect(request.bodyFields['client_secret'], isNotEmpty);
          return http.Response(
            jsonEncode({
              'access_token': 'access-token',
              'refresh_token': 'refresh-token',
              'expires_in': 3600,
              'token_type': 'Bearer',
              'user_id': 42,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        case '/p1/users/tester':
          expect(request.headers['authorization'], 'Bearer access-token');
          return http.Response(
            jsonEncode({
              'id': 42,
              'username': 'tester',
              'nickname': '测试用户',
              'avatar': {'large': 'https://lain.bgm.tv/profile.jpg'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        case '/subject/ep/9122/new_reply':
          expect(request.url.queryParameters['ajax'], '1');
          expect(request.headers['referer'], 'https://bgm.tv/ep/9122');
          expect(request.headers['cookie'], contains('chii_auth=signed-in'));
          expect(request.bodyFields, {
            'lastview': '',
            'formhash': 'form-token',
            'content': '章节评论',
            'submit': 'submit',
          });
          return http.Response(
            jsonEncode({
              'posts': {
                'main': <String, dynamic>{},
                'sub': <String, dynamic>{},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        case '/p1/subjects/99':
          return http.Response('{"id":99,"interest":null}', 200);
        case '/p1/collections/subjects/99':
          expect(request.method, 'PUT');
          expect(request.headers['authorization'], 'Bearer access-token');
          return http.Response('', 204);
        case '/group/topic/77/new_reply':
          expect(request.url.queryParameters['ajax'], '1');
          expect(request.headers['referer'], 'https://bgm.tv/group/topic/77');
          expect(request.bodyFields['content'], '超展开评论');
          expect(request.bodyFields['formhash'], 'form-token');
          return http.Response(
            jsonEncode({'status': 'ok'}),
            200,
            headers: {'content-type': 'application/json'},
          );
      }
      return http.Response('not found', 404);
    });
    final sessionClient = CookieSessionClient(rawClient, cookies);
    final auth = AuthService(
      client: sessionClient,
      cookies: cookies,
      vault: vault,
      appId: 'test-app',
      appSecret: 'test-secret',
    );
    await auth.initialize();

    final challenge = await auth.beginLogin();
    final captcha = await auth.loadCaptcha();
    await expectLater(
      auth.login(
        email: 'user@example.com',
        password: 'temporary-password',
        captcha: 'wrong',
        challenge: challenge,
      ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          '验证码输入错误',
        ),
      ),
    );
    await auth.login(
      email: 'user@example.com',
      password: 'temporary-password',
      captcha: '1234',
      challenge: challenge,
    );

    expect(captcha, [1, 2, 3]);
    expect(auth.isLoggedIn, isTrue);
    expect(auth.user?.username, 'tester');
    expect(await auth.validAccessToken(), 'access-token');

    final repository = RemoteBangumiRepository(
      apiClient: ApiClient(client: sessionClient, authService: auth),
    );
    await repository.createEpisodeComment(9122, ' 章节评论 ');
    var collectionNotifications = 0;
    repository.collectionChanges.addListener(() => collectionNotifications++);
    await repository.updateSubjectCollection(
      99,
      type: 3,
      rate: 0,
      comment: '',
      isPrivate: false,
      wasCollected: false,
    );
    expect(repository.effectiveSubjectCollectionCount('tester', 0), 1);
    expect(repository.effectiveSubjectCollectionCount('tester', 1), 1);
    expect(collectionNotifications, 1);
    await repository.createTopicReply(
      Topic(
        id: 77,
        type: 'group',
        title: '测试讨论',
        group: '测试小组',
        replies: 0,
        updatedAt: DateTime(2026),
      ),
      ' 超展开评论 ',
    );
  });
}
