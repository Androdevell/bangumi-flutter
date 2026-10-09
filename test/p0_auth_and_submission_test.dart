import 'dart:async';
import 'dart:convert';

import 'package:bangumi_flutter/core/auth/auth_models.dart';
import 'package:bangumi_flutter/core/auth/auth_service.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/network/cookie_session_client.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _userKey = 'bangumi.auth.user.v1';
const _tokenKey = 'bangumi.auth.token.v1';

Future<void> _seed(
  SecureVault vault, {
  bool expired = true,
  String hash = '',
}) async {
  await vault.write(
    _userKey,
    jsonEncode({'username': 'tester', 'nickname': '测试用户', 'formHash': hash}),
  );
  await vault.write(
    _tokenKey,
    jsonEncode({
      'access_token': 'old-access',
      'refresh_token': 'old-refresh',
      'expires_in': 3600,
      'saved_at':
          DateTime.now()
              .subtract(Duration(hours: expired ? 2 : 0))
              .millisecondsSinceEpoch,
    }),
  );
}

http.Response _tokenResponse() => http.Response(
  jsonEncode({
    'access_token': 'new-access',
    'refresh_token': 'new-refresh',
    'expires_in': 3600,
  }),
  200,
  headers: {'set-cookie': 'chii_auth=new-session; Path=/; Secure'},
);

Future<AuthService> _auth(http.Client client, SecureVault vault) async {
  final cookies = PersistentCookieStore(vault);
  await cookies.initialize();
  final auth = AuthService(
    client: CookieSessionClient(client, cookies),
    cookies: cookies,
    vault: vault,
    appId: 'test-app',
    appSecret: 'test-secret',
  );
  await auth.initialize();
  addTearDown(auth.dispose);
  return auth;
}

void main() {
  test('temporary vault read failure preserves stored ciphertext', () async {
    final vault = _UnavailableVault();
    await _seed(vault);
    final auth = await _auth(MockClient((_) async => _tokenResponse()), vault);
    vault.unavailable = true;
    await auth.initialize();
    vault.unavailable = false;
    expect(await vault.read(_tokenKey), isNotNull);
    expect(await vault.read(_userKey), isNotNull);
  });

  test(
    'unconfigured login fails explicitly without making a network request',
    () async {
      var requests = 0;
      final vault = MemorySecureVault();
      final auth = AuthService(
        client: MockClient((_) async {
          requests++;
          return http.Response('', 200);
        }),
        cookies: PersistentCookieStore(vault),
        vault: vault,
        appId: '',
        appSecret: '',
      );
      addTearDown(auth.dispose);
      await expectLater(auth.beginLogin(), throwsA(isA<AuthException>()));
      expect(requests, 0);
    },
  );

  test(
    'failed refresh and reauthorization clear credentials and notify UI',
    () async {
      final vault = MemorySecureVault();
      await _seed(vault, hash: 'expired-form');
      final paths = <String>[];
      final auth = await _auth(
        MockClient((request) async {
          paths.add(request.url.path);
          return http.Response('unauthorized', 401);
        }),
        vault,
      );
      var notifications = 0;
      auth.addListener(() => notifications++);
      expect(await auth.validAccessToken(), isNull);
      expect(paths, ['/oauth/access_token', '/oauth/authorize']);
      expect(auth.isLoggedIn, isFalse);
      expect(notifications, 1);
      expect(await vault.read(_tokenKey), isNull);
      expect(await vault.read(_userKey), isNull);
    },
  );

  test('refresh is single flight and persists the new token', () async {
    final vault = MemorySecureVault();
    await _seed(vault);
    final started = Completer<void>();
    final response = Completer<http.Response>();
    var requests = 0;
    final auth = await _auth(
      MockClient((_) {
        requests++;
        started.complete();
        return response.future;
      }),
      vault,
    );
    final first = auth.refreshAccessToken();
    final second = auth.refreshAccessToken();
    await started.future;
    response.complete(_tokenResponse());
    expect(await Future.wait([first, second]), [true, true]);
    expect(requests, 1);
    expect(await auth.validAccessToken(), 'new-access');
    expect(await vault.read(_tokenKey), contains('new-access'));
  });

  test(
    'logout invalidates pending refresh including response cookies',
    () async {
      final vault = MemorySecureVault();
      await _seed(vault);
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final auth = await _auth(
        MockClient((_) {
          started.complete();
          return response.future;
        }),
        vault,
      );
      final refresh = auth.refreshAccessToken();
      await started.future;
      await auth.logout();
      response.complete(_tokenResponse());
      expect(await refresh, isFalse);
      expect(auth.isLoggedIn, isFalse);
      expect(await vault.read(_tokenKey), isNull);
      expect(await vault.read(_userKey), isNull);
      expect(await vault.read('bangumi.cookies.v1'), isNull);
      final restored = await _auth(
        MockClient((_) async => _tokenResponse()),
        vault,
      );
      expect(restored.isLoggedIn, isFalse);
    },
  );

  test(
    'logout waits for credential write then deletes it, never resurrects session',
    () async {
      final vault = _BlockingVault();
      await _seed(vault);
      final auth = await _auth(
        MockClient((_) async => _tokenResponse()),
        vault,
      );
      vault.block = true;
      final refresh = auth.refreshAccessToken();
      await vault.writeStarted.future;
      final logout = auth.logout();
      expect(auth.isLoggedIn, isFalse);
      vault.allowWrite.complete();
      await logout;
      expect(await refresh, isFalse);
      expect(await vault.read(_tokenKey), isNull);
      expect(await vault.read(_userKey), isNull);
    },
  );

  test(
    'expired authenticated writes never downgrade to anonymous API calls',
    () async {
      final vault = MemorySecureVault();
      await _seed(vault);
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return http.Response('unauthorized', 401);
      });
      final auth = await _auth(client, vault);
      final api = ApiClient(client: client, authService: auth);
      await expectLater(
        api.put('p1/collections/subjects/1'),
        throwsA(isA<ApiException>()),
      );
      expect(paths, ['/oauth/access_token']);
    },
  );

  for (final status in [302, 303, 307, 401, 500]) {
    test(
      'web form rejects HTTP $status and preserves UTF-8 error text',
      () async {
        final api = ApiClient(
          client: MockClient((request) async {
            expect(request.followRedirects, isFalse);
            return http.Response.bytes(
              utf8.encode('{"message":"会话已过期"}'),
              status,
              headers: {
                'location': '/login',
                'content-type': 'application/json',
              },
            );
          }),
        );
        await expectLater(
          api.postWebForm('new_reply', fields: {}),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', status)
                .having(
                  (e) => e.toString(),
                  'Chinese error',
                  contains('会话已过期'),
                ),
          ),
        );
      },
    );
  }

  for (final body in ['', '<html>login</html>', 'null', '{}', '[]']) {
    test(
      'comment and topic reply reject missing confirmation: "$body"',
      () async {
        final vault = MemorySecureVault();
        await _seed(vault, expired: false, hash: 'form-token');
        final client = MockClient((_) async => http.Response(body, 200));
        final auth = await _auth(client, vault);
        final repository = RemoteBangumiRepository(
          apiClient: ApiClient(client: client, authService: auth),
        );
        await expectLater(
          repository.createEpisodeComment(1, 'draft'),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          repository.createTopicReply(_topic, 'draft'),
          throwsA(isA<ApiException>()),
        );
      },
    );
  }

  test(
    'login redirect propagates through episode and topic reply repositories',
    () async {
      final vault = MemorySecureVault();
      await _seed(vault, expired: false, hash: 'form-token');
      final client = MockClient(
        (_) async => http.Response('', 302, headers: {'location': '/login'}),
      );
      final auth = await _auth(client, vault);
      final repository = RemoteBangumiRepository(
        apiClient: ApiClient(client: client, authService: auth),
      );
      await expectLater(
        repository.createEpisodeComment(1, 'draft'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        repository.createTopicReply(_topic, 'draft'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('anonymous comments are rejected before sending', () async {
    var requests = 0;
    final repository = RemoteBangumiRepository(
      apiClient: ApiClient(
        client: MockClient((_) async {
          requests++;
          return http.Response('{"status":"ok"}', 200);
        }),
      ),
    );
    await expectLater(
      repository.createEpisodeComment(1, 'draft'),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      repository.createTopicReply(_topic, 'draft'),
      throwsA(isA<ApiException>()),
    );
    expect(requests, 0);
  });
}

final _topic = Topic(
  id: 1,
  type: 'group',
  title: 'topic',
  group: '',
  replies: 0,
  updatedAt: DateTime(2026),
);

class _BlockingVault extends MemorySecureVault {
  bool block = false;
  final writeStarted = Completer<void>();
  final allowWrite = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    if (block && key == _tokenKey) {
      writeStarted.complete();
      await allowWrite.future;
    }
    await super.write(key, value);
  }
}

class _UnavailableVault extends MemorySecureVault {
  bool unavailable = false;

  @override
  Future<String?> read(String key) async {
    if (unavailable) throw StateError('Keystore temporarily unavailable');
    return super.read(key);
  }
}
