import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/app/theme_controller.dart';
import 'package:bangumi_flutter/core/auth/auth_service.dart';
import 'package:bangumi_flutter/core/auth/auth_models.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/network/cookie_session_client.dart';
import 'package:bangumi_flutter/core/settings/app_preferences.dart';
import 'package:bangumi_flutter/core/settings/theme_preferences.dart';
import 'package:bangumi_flutter/core/update/app_update_service.dart';
import 'package:bangumi_flutter/core/update/update_download_service.dart';
import 'package:bangumi_flutter/core/diagnostics/network_diagnostics.dart';
import 'package:bangumi_flutter/data/repositories/remote_privacy_repository.dart';
import 'package:bangumi_flutter/features/auth/login_page.dart';
import 'package:bangumi_flutter/features/profile/theme_settings_page.dart';
import 'comment_experience_test.dart' show host;
import 'community_extensions_test.dart' show authenticated, png;
import 'privacy_and_image_regression_test.dart' show privacyJson;

void main() {
  test('update download rejects a redirect outside trusted hosts', () async {
    final folder = await Directory.systemTemp.createTemp(
      'bangumi-update-redirect-',
    );
    addTearDown(() => folder.delete(recursive: true));
    var requests = 0;
    final download = UpdateDownloadService(
      directoryProvider: () async => folder,
      clientFactory:
          () => MockClient((_) async {
            requests++;
            return http.Response(
              '',
              302,
              headers: {'location': 'https://untrusted.example/file'},
            );
          }),
    );
    addTearDown(download.dispose);
    await download.download(
      ComposeUpdateAsset(
        name: 'bangumi-1.2.8-windows-x64.zip',
        url: Uri.parse(
          'https://github.com/Androdevell/bangumi-flutter/releases/download/v1.2.8/bangumi-1.2.8-windows-x64.zip',
        ),
        size: 42,
      ),
    );
    expect(requests, 1);
    expect(download.file, isNull);
    expect(download.error, 'downloadFailed');
  });
  test(
    'cancelling a pending download never exposes a completed package',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'bangumi-update-cancel-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final started = Completer<void>(), response = Completer<http.Response>();
      final download = UpdateDownloadService(
        directoryProvider: () async => folder,
        clientFactory:
            () => MockClient((_) async {
              started.complete();
              return response.future;
            }),
      );
      addTearDown(download.dispose);
      final operation = download.download(
        ComposeUpdateAsset(
          name: 'bangumi-1.2.8-windows-x64.zip',
          url: Uri.parse(
            'https://github.com/Androdevell/bangumi-flutter/releases/download/v1.2.8/bangumi-1.2.8-windows-x64.zip',
          ),
          size: 3,
        ),
      );
      await started.future;
      await download.cancel();
      response.complete(http.Response.bytes([1, 2, 3], 200));
      await operation;
      expect(download.file, isNull);
      expect(download.error, 'downloadCancelled');
      expect(download.busy, false);
    },
  );
  testWidgets('theme presets can be applied on a narrow large-text screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = AppPreferences(MemorySecureVault());
    final controller = ThemeController(
      preferences,
      const ComposeThemePreferences(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 1000),
            textScaler: TextScaler.linear(1.6),
          ),
          child: ThemeSettingsPage(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('森语绿'));
    await tester.tap(find.text('森语绿'));
    await tester.pumpAndSettle();
    final apply = find.widgetWithText(FilledButton, '应用配色').last;
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(controller.settings.preset, 'forest');
    expect((await preferences.load()).theme.seed, themePresets['forest']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'temporary refresh failure keeps credentials and restored web cookies',
    () async {
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
          'expires_in': 1,
          'saved_at': 1,
        }),
      );
      final cookies = PersistentCookieStore(vault);
      await cookies.capture(
        Uri.parse('https://bgm.tv/'),
        'chii_auth=fixture; Path=/; Secure; Max-Age=2592000',
      );
      final client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      final auth = AuthService(client: client, cookies: cookies, vault: vault);
      addTearDown(auth.dispose);
      addTearDown(client.close);
      await auth.initialize();
      await expectLater(
        auth.validAccessToken(),
        throwsA(isA<http.ClientException>()),
      );
      expect(auth.isLoggedIn, true);
      expect(await vault.read('bangumi.auth.token.v1'), isNotNull);
      final restored = PersistentCookieStore(vault);
      await restored.initialize();
      expect(
        restored.headerFor(Uri.parse('https://bgm.tv/settings')),
        contains('chii_auth=fixture'),
      );
    },
  );

  testWidgets(
    'web revalidation shows captcha even when OAuth is already restored',
    (tester) async {
      var captchaCalls = 0;
      final (api, auth) = await authenticated(
        MockClient((request) async {
          if (request.url.path == '/login') {
            return http.Response(
              '<form id="loginForm"><input name="once" value="fixture"></form>',
              200,
            );
          }
          if (request.url.path == '/signup/captcha') {
            captchaCalls++;
            return http.Response.bytes(png, 200);
          }
          throw StateError('Unexpected request');
        }),
      );
      addTearDown(api.close);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(authService: auth, expectedUsername: 'tester'),
        ),
      );
      await tester.pumpAndSettle();
      expect(captchaCalls, 1);
      expect(find.byType(TextFormField), findsNWidgets(3));
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'web verification cannot replace the current account with another cookie identity',
    () async {
      final (api, auth) = await authenticated(
        MockClient(
          (_) async => http.Response(
            '<main id="main"><div id="header"><h1>Other</h1></div></main>'
            '<div class="idBadgerNeue"><a class="avatar" href="/user/other"></a></div>',
            200,
          ),
        ),
      );
      addTearDown(api.close);
      addTearDown(auth.dispose);
      await expectLater(
        auth.beginLogin(expectedUsername: 'tester'),
        throwsA(isA<AuthException>()),
      );
      expect(auth.user!.username, 'tester');
    },
  );

  test(
    'privacy waits for independent readback and never repeats the write or sends stale cookies',
    () async {
      var patches = 0, readbacks = 0;
      final (api, auth) = await authenticated(
        MockClient((request) async {
          expect(request.headers['cookie'] ?? '', isNot(contains('chii_auth')));
          expect(request.headers['authorization'], 'Bearer synthetic');
          if (request.method == 'PATCH') {
            patches++;
            return http.Response(
              jsonEncode(privacyJson({'follow': 'none'})),
              200,
            );
          }
          if (patches > 0) readbacks++;
          return http.Response(
            jsonEncode(privacyJson(readbacks >= 2 ? {'follow': 'none'} : {})),
            200,
          );
        }),
      );
      addTearDown(api.close);
      addTearDown(auth.dispose);
      final repo = RemotePrivacyRepository(api, delay: (_) async {});
      final old = await repo.load();
      final saved = await repo.save(old, {'follow': 'none'});
      expect(saved.settings['follow'], 'none');
      expect(patches, 1);
      expect(readbacks, 2);
      expect((await repo.load()).settings['follow'], 'none');
    },
  );

  test(
    'update metadata retains notes and selects only the correct platform package',
    () async {
      final service = AppUpdateService(
        versionProvider: () async => '1.2.7+2027',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'tag_name': 'v1.2.8',
              'body': '## 修复\n- 登录恢复',
              'html_url':
                  'https://github.com/Androdevell/bangumi-flutter/releases/tag/v1.2.8',
              'assets': [
                for (final suffix in ['arm64-v8a.apk', 'windows-x64.zip'])
                  {
                    'name': 'bangumi-1.2.8-$suffix',
                    'size': 42,
                    'browser_download_url':
                        'https://github.com/Androdevell/bangumi-flutter/releases/download/v1.2.8/bangumi-1.2.8-$suffix',
                  },
                {
                  'name': 'bangumi-1.2.8-arm64-v8a.apk',
                  'size': 42,
                  'browser_download_url':
                      'https://untrusted.example/download.apk',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(service.close);
      final result = await service.check();
      expect(result.updateAvailable, true);
      expect(result.notes, contains('登录恢复'));
      expect(result.assets.length, 2);
      expect(result.assetFor(android: true)!.name, endsWith('arm64-v8a.apk'));
      expect(
        result.assetFor(android: false)!.name,
        endsWith('windows-x64.zip'),
      );
    },
  );

  for (final valid in [true, false]) {
    test(
      'download checksum valid=$valid only exposes complete verified files',
      () async {
        final folder = await Directory.systemTemp.createTemp(
          'bangumi-update-test-',
        );
        addTearDown(() => folder.delete(recursive: true));
        final bytes = utf8.encode('synthetic package');
        final download = UpdateDownloadService(
          directoryProvider: () async => folder,
          clientFactory:
              () => MockClient((_) async => http.Response.bytes(bytes, 200)),
        );
        addTearDown(download.dispose);
        await download.download(
          ComposeUpdateAsset(
            name: 'bangumi-1.2.8-windows-x64.zip',
            url: Uri.parse(
              'https://github.com/Androdevell/bangumi-flutter/releases/download/v1.2.8/bangumi-1.2.8-windows-x64.zip',
            ),
            size: bytes.length,
            digest: 'sha256:${valid ? sha256.convert(bytes) : '0' * 64}',
          ),
        );
        expect(download.busy, false);
        expect(download.verified, valid);
        if (valid) {
          expect(await download.file!.readAsBytes(), bytes);
        } else {
          expect(download.file, isNull);
          expect(download.error, 'downloadIntegrity');
        }
        final parts =
            await folder
                .list(recursive: true)
                .where((e) => e.path.endsWith('.part'))
                .toList();
        expect(parts, isEmpty);
      },
    );
  }

  test(
    'theme selection survives an application upgrade and invalid schema falls back',
    () async {
      final vault = MemorySecureVault();
      final prefs = AppPreferences(vault);
      final controller = ThemeController(
        prefs,
        const ComposeThemePreferences(),
      );
      addTearDown(controller.dispose);
      await controller.apply(
        ComposeThemePreferences(
          source: ThemeColorSource.system,
          seed: themePresets['forest']!,
          preset: 'forest',
          mode: ThemeMode.dark,
        ),
      );
      final restored = (await AppPreferences(vault).load()).theme;
      expect(restored.source, ThemeColorSource.system);
      expect(restored.seed, themePresets['forest']);
      expect(restored.mode, ThemeMode.dark);
      expect(ComposeThemePreferences.decode('broken').preset, 'sakura');
    },
  );

  test(
    'network diagnostics measures uncached response duration without credentials',
    () async {
      final diagnostic = NetworkDiagnosticsService(
        client: MockClient((request) async {
          expect(request.headers['authorization'], isNull);
          expect(request.headers['cookie'], isNull);
          expect(request.headers['cache-control'], 'no-cache');
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return http.Response('ok', 200);
        }),
      );
      addTearDown(diagnostic.close);
      final result = await diagnostic.sample(
        'API',
        Uri.parse('https://example.test/'),
      );
      expect(result.error, isNull);
      expect(result.totalMs, greaterThanOrEqualTo(25));
    },
  );
}
