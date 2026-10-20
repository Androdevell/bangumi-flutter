import 'package:http/http.dart' as http;
import '../../core/auth/auth_service.dart';
import '../../core/auth/secure_vault.dart';
import '../../core/network/api_client.dart';
import '../../core/network/app_image_cache.dart';
import '../../core/network/cookie_session_client.dart';
import '../../core/network/platform_http_client.dart';
import '../../core/network/image_transport.dart';
import '../../core/network/third_party_preview_service.dart';
import '../../core/settings/app_preferences.dart';
import '../../core/media/rich_image_policy.dart';
import '../../core/cache/calendar_snapshot.dart';
import '../../data/bangumi_repository.dart';

/// 应用装配根；共享客户端只由这里关闭一次。
class AppDependencies {
  AppDependencies._({
    required this.preferences,
    required this.settings,
    required this.auth,
    required this.repository,
    required http.Client apiTransport,
    required http.Client imageTransport,
  }) : _apiTransport = apiTransport,
       _imageTransport = imageTransport;

  final AppPreferences preferences;
  final AppPreferenceSnapshot settings;
  final AuthService auth;
  final RemoteBangumiRepository repository;
  final http.Client _apiTransport;
  final http.Client _imageTransport;
  Future<void>? _closing;

  static Future<AppDependencies> initialize() async {
    final vault = PlatformSecureVault();
    final preferences = AppPreferences(vault);
    final settings = await preferences.load();
    await RichImagePolicy.instance.initialize(vault);
    final cookies = PersistentCookieStore(vault);
    await cookies.initialize();
    final apiTransport = CookieSessionClient(
      createPlatformHttpClient(),
      cookies,
    );
    final imageTransport = ImageTransport(createPlatformHttpClient());
    final auth = AuthService(
      client: apiTransport,
      cookies: cookies,
      vault: vault,
    );
    try {
      await auth.initialize();
      AppImageCache.initialize(imageTransport);
      final repository = RemoteBangumiRepository(
        calendarStore: CalendarSnapshotStore(
          vault,
          const String.fromEnvironment(
            'BGM_API_BASE_URL',
            defaultValue: 'https://next.bgm.tv/',
          ),
        ),
        apiClient: ApiClient(
          client: apiTransport,
          authService: auth,
          closeClient: false,
        ),
        previewService: ThirdPartyPreviewService(
          enabled: settings.thirdPartyPreviews,
          persist: preferences.setThirdPartyPreviews,
        ),
      );
      return AppDependencies._(
        preferences: preferences,
        settings: settings,
        auth: auth,
        repository: repository,
        apiTransport: apiTransport,
        imageTransport: imageTransport,
      );
    } on Object {
      auth.dispose();
      apiTransport.close();
      imageTransport.close();
      rethrow;
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    repository.close();
    auth.dispose();
    try {
      await AppImageCache.dispose();
    } finally {
      _apiTransport.close();
      _imageTransport.close();
    }
  }
}
