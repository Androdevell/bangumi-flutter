import 'dart:io';

import 'package:bangumi_flutter/core/auth/auth_service.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/network/cookie_session_client.dart';
import 'package:bangumi_flutter/core/network/platform_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Windows transport loads the real login form and captcha',
    () async {
      if (!Platform.isWindows) return;
      final vault = MemorySecureVault();
      final cookies = PersistentCookieStore(vault);
      await cookies.initialize();
      final client = CookieSessionClient(createPlatformHttpClient(), cookies);
      addTearDown(client.close);
      final auth = AuthService(client: client, cookies: cookies, vault: vault);

      final challenge = await auth.beginLogin();
      final captcha = await auth.loadCaptcha();

      expect(challenge.hiddenFields, isNotEmpty);
      expect(captcha, isNotEmpty);
    },
    skip: 'Live network probe',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
