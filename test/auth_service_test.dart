import 'dart:convert';

import 'package:bangumi_flutter/core/auth/auth_service.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/network/cookie_session_client.dart';
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
          return http.Response(
            '',
            302,
            headers: {'location': 'http://localhost/callback?code=oauth-code'},
          );
        case '/oauth/access_token':
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
  });
}
