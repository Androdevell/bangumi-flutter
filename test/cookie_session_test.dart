import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/network/cookie_session_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('persists and sends matching response cookies', () async {
    final vault = MemorySecureVault();
    final firstStore = PersistentCookieStore(vault);
    await firstStore.initialize();
    final firstClient = CookieSessionClient(
      MockClient(
        (_) async => http.Response(
          'ok',
          200,
          headers: {
            'set-cookie':
                'chii_auth=secret; Path=/; Secure; HttpOnly, '
                'session=active; Path=/; Max-Age=3600',
          },
        ),
      ),
      firstStore,
    );

    await firstClient.get(Uri.parse('https://bgm.tv/login'));

    final restoredStore = PersistentCookieStore(vault);
    await restoredStore.initialize();
    late String? sentCookie;
    final restoredClient = CookieSessionClient(
      MockClient((request) async {
        sentCookie = request.headers['cookie'];
        return http.Response('ok', 200);
      }),
      restoredStore,
    );
    await restoredClient.get(Uri.parse('https://bgm.tv/'));

    expect(sentCookie, contains('chii_auth=secret'));
    expect(sentCookie, contains('session=active'));
  });
}
