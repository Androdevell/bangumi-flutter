import 'package:flutter/material.dart';

import 'app/bangumi_app.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/secure_vault.dart';
import 'core/network/api_client.dart';
import 'core/network/app_image_cache.dart';
import 'core/network/cookie_session_client.dart';
import 'core/network/platform_http_client.dart';
import 'data/bangumi_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final vault = PlatformSecureVault();
  final cookieStore = PersistentCookieStore(vault);
  await cookieStore.initialize();

  final apiTransport = CookieSessionClient(
    createPlatformHttpClient(),
    cookieStore,
  );
  final imageTransport = createPlatformHttpClient();
  final authService = AuthService(
    client: apiTransport,
    cookies: cookieStore,
    vault: vault,
  );
  await authService.initialize();
  AppImageCache.initialize(imageTransport);
  runApp(
    BangumiApp(
      authService: authService,
      repository: RemoteBangumiRepository(
        apiClient: ApiClient(client: apiTransport, authService: authService),
      ),
    ),
  );
}
