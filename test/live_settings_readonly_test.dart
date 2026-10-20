import 'package:flutter_test/flutter_test.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/auth/auth_service.dart';
import 'package:bangumi_flutter/core/network/cookie_session_client.dart';
import 'package:bangumi_flutter/core/network/platform_http_client.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/data/repositories/remote_account_settings_repository.dart';
import 'package:bangumi_flutter/data/repositories/remote_privacy_repository.dart';

/// 显式启用的本机只读探针：只读取已有会话，响应 Cookie 只保存到内存。
void main() {
  test(
    'saved Windows session reads personal settings without logging in',
    () async {
      final stored = PlatformSecureVault();
      final memory = MemorySecureVault();
      for (final key in [
      'bangumi.cookies.v1',
      AuthService.sessionStorageKey,
        'bangumi.auth.user.v1',
        'bangumi.auth.token.v1',
      ]) {
        final value = await stored.read(key);
        if (value != null) await memory.write(key, value);
      }
      final cookies = PersistentCookieStore(memory);
      await cookies.initialize();
      final client = CookieSessionClient(createPlatformHttpClient(), cookies);
      final auth = AuthService(client: client, cookies: cookies, vault: memory);
      await auth.initialize();
      final api = ApiClient(client: client, authService: auth);
      addTearDown(api.close);
      addTearDown(auth.dispose);
      expect(auth.isLoggedIn, true);
      final repository = RemoteAccountSettingsRepository(api, onChanged: () {});
      final settings = await repository.load();
      expect(settings.timezones, isNotEmpty);
      expect(settings.fields.containsKey('nickname'), true);
      final privacy = await RemotePrivacyRepository(api).load();
      expect(privacy.settings.length, 7);
    },
    skip: !const bool.fromEnvironment('BGM_LIVE_SETTINGS_READONLY'),
  );
}
