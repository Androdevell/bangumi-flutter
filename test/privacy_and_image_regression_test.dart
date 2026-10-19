import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/app/state/session_scope.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/network/image_request_headers.dart';
import 'package:bangumi_flutter/core/network/safe_image_file_service.dart';
import 'package:bangumi_flutter/data/repositories/remote_privacy_repository.dart';
import 'package:bangumi_flutter/domain/models/privacy_settings.dart';
import 'package:bangumi_flutter/domain/repositories/privacy_repository.dart';
import 'package:bangumi_flutter/features/profile/privacy/privacy_controller.dart';
import 'package:bangumi_flutter/features/profile/privacy/privacy_page.dart';
import 'package:bangumi_flutter/widgets/settings_choice.dart';
import 'package:bangumi_flutter/core/localization/app_localizations.dart';
import 'community_extensions_test.dart' show authenticated, session, png;
import 'comment_experience_test.dart' show host;

Map<String, Object> privacyJson([Map<String, String> edits = const {}]) => {
  'settings': {
    for (final field in PrivacyField.values) field: PrivacyAudience.all,
    ...edits,
  },
  'preferences': {
    'showNsfwSubject': false,
    'canSetNsfwSubject': false,
    'allowNsfw': true,
  },
};

void main() {
  test(
    'transport failure after PATCH is uncertain and is not retried',
    () async {
      var patches = 0;
      final (api, auth) = await authenticated(
        MockClient((request) async {
          if (request.method == 'PATCH') {
            patches++;
            throw http.ClientException('synthetic connection lost');
          }
          return http.Response(jsonEncode(privacyJson()), 200);
        }),
      );
      addTearDown(api.close);
      addTearDown(auth.dispose);
      final repository = RemotePrivacyRepository(api);
      final original = await repository.load();
      await expectLater(
        repository.save(original, {'follow': 'none'}),
        throwsA(
          isA<ApiException>().having((e) => e.outcomeUnknown, 'unknown', true),
        ),
      );
      expect(patches, 1);
    },
  );
  test(
    'logout prevents saving a previous account form before transport',
    () async {
      var patches = 0;
      final (api, auth) = await authenticated(
        MockClient((request) async {
          if (request.method == 'PATCH') patches++;
          return http.Response(jsonEncode(privacyJson()), 200);
        }),
      );
      addTearDown(api.close);
      addTearDown(auth.dispose);
      final repository = RemotePrivacyRepository(api);
      final original = await repository.load();
      await auth.logout();
      await expectLater(
        repository.save(original, {'follow': 'none'}),
        throwsA(isA<ApiException>()),
      );
      expect(patches, 0);
    },
  );
  test(
    'privacy parser rejects missing and unsupported values without defaults',
    () {
      expect(
        () => ComposePrivacySettings.fromJson({'settings': {}}, session),
        throwsFormatException,
      );
      expect(
        () => ComposePrivacySettings.fromJson(
          privacyJson({'follow': 'friends'}),
          session,
        ),
        throwsFormatException,
      );
      final parsed = ComposePrivacySettings.fromJson(privacyJson(), session);
      expect(() => parsed.settings['follow'] = 'none', throwsUnsupportedError);
    },
  );
  test(
    'privacy sends only edited settings and verifies fresh read, preserving preferences',
    () async {
      var saved = <String, String>{};
      var patches = 0;
      final (api, auth) = await authenticated(
        MockClient((request) async {
          if (request.method == 'PATCH') {
            patches++;
            expect(jsonDecode(request.body), {
              'settings': {'privateMessage': 'friends'},
            });
            saved = {'privateMessage': 'friends'};
          }
          return http.Response(jsonEncode(privacyJson(saved)), 200);
        }),
      );
      addTearDown(api.close);
      addTearDown(auth.dispose);
      final repository = RemotePrivacyRepository(api);
      final original = await repository.load();
      final result = await repository.save(original, {
        'privateMessage': 'friends',
      });
      expect(result.settings['privateMessage'], 'friends');
      expect(result.settings['follow'], 'all');
      expect(patches, 1);
    },
  );
  test('conflicting edits and invalid fields never send PATCH', () async {
    var reads = 0;
    var patches = 0;
    final (api, auth) = await authenticated(
      MockClient((request) async {
        if (request.method == 'PATCH') patches++;
        reads++;
        return http.Response(
          jsonEncode(privacyJson(reads > 1 ? {'privateMessage': 'none'} : {})),
          200,
        );
      }),
    );
    addTearDown(api.close);
    addTearDown(auth.dispose);
    final repository = RemotePrivacyRepository(api);
    final original = await repository.load();
    await expectLater(
      repository.save(original, {'privateMessage': 'friends'}),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'privacyConflict',
        ),
      ),
    );
    await expectLater(
      repository.save(original, {'canSetNsfwSubject': 'true'}),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      repository.save(original, {'follow': 'friends'}),
      throwsA(isA<ApiException>()),
    );
    expect(patches, 0);
  });
  test(
    'save is uncertain when readback disagrees; no automatic repeated PATCH',
    () async {
      var patches = 0;
      final (api, auth) = await authenticated(
        MockClient((request) async {
          if (request.method == 'PATCH') patches++;
          return http.Response(jsonEncode(privacyJson()), 200);
        }),
      );
      addTearDown(api.close);
      addTearDown(auth.dispose);
      final repository = RemotePrivacyRepository(api);
      final original = await repository.load();
      await expectLater(
        repository.save(original, {'follow': 'none'}),
        throwsA(
          isA<ApiException>().having((e) => e.outcomeUnknown, 'unknown', true),
        ),
      );
      expect(patches, 1);
    },
  );
  test(
    'controller requires reload after unknown write and rejects old-session result',
    () async {
      final repository = FakePrivacy();
      final controller = PrivacyController(repository);
      addTearDown(controller.dispose);
      addTearDown(repository.changes.dispose);
      await controller.load();
      controller.edit('follow', 'none');
      repository.uncertain = true;
      expect(await controller.save(), false);
      expect(controller.canSave, false);
      await controller.save();
      expect(repository.saves, 1);
      await controller.load();
      controller.edit('follow', 'none');
      repository.pending = Completer();
      final saving = controller.save();
      repository.changes.notifyListeners();
      repository.pending!.complete(
        ComposePrivacySettings.fromJson(
          privacyJson({'follow': 'none'}),
          session,
        ),
      );
      expect(await saving, false);
      expect(controller.loaded, false);
    },
  );
  test('reload failure cannot re-enable uncertain form', () async {
    final repository = FakePrivacy();
    final controller = PrivacyController(repository);
    addTearDown(controller.dispose);
    addTearDown(repository.changes.dispose);
    await controller.load();
    controller.edit('follow', 'none');
    repository.uncertain = true;
    await controller.save();
    repository.failLoad = true;
    await controller.load();
    expect(controller.loaded, false);
    expect(controller.canSave, false);
  });
  for (final locale in ['zh', 'en', 'ja']) {
    testWidgets('privacy page options and save in $locale', (tester) async {
      tester.view.physicalSize = const Size(600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakePrivacy();
      addTearDown(repository.changes.dispose);
      final strings = AppLocalizations(Locale(locale));
      await tester.pumpWidget(
        host(PrivacyPage(repository: repository), locale: locale),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SettingsChoiceTile), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('privacy-save')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('privacy-follow-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.t('privacy_none')).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('privacy-save')));
      await tester.tap(find.byKey(const ValueKey('privacy-save')));
      await tester.pumpAndSettle();
      expect(repository.saves, 1);
      expect(repository.lastEdits, {'follow': 'none'});
      expect(find.text(strings.t('privacySaved')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  test(
    'image headers do not leak credentials or caller referrer to spoofed hosts',
    () {
      for (final host in [
        'img9.doubanio.com',
        'doubanio.com',
        'doubanio.com.example.com',
        'evildoubanio.com',
        'example.com',
      ]) {
        final headers = imageRequestHeaders(Uri.parse('https://$host/a.jpg'), {
          'Cookie': 'secret',
          'Authorization': 'secret',
          'Proxy-Authorization': 'secret',
          'Referer': 'https://private.example/',
          'If-None-Match': 'etag',
        });
        expect(
          headers.keys.any(
            (key) =>
                key.toLowerCase().contains('authorization') ||
                key.toLowerCase() == 'cookie',
          ),
          false,
        );
        expect(headers['If-None-Match'], 'etag');
        expect(
          headers['Referer'],
          host == 'doubanio.com' || host == 'img9.doubanio.com'
              ? 'https://m.douban.com/'
              : null,
        );
      }
    },
  );
  test(
    'real image service rebuilds safe headers on each redirect and decodes image',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://img9.doubanio.com/a.png'},
          );
        }
        if (requests.length == 2) {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://example.com/a.png'},
          );
        }
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      addTearDown(client.close);
      final service = SafeImageFileService(
        client,
        lookup: (_) async => [InternetAddress('93.184.216.34')],
      );
      final response = await service.get(
        'https://example.com/start',
        headers: {'Cookie': 'secret', 'Referer': 'https://private.example/'},
      );
      expect(response.statusCode, 200);
      expect(requests.map((request) => request.headers['referer']), [
        null,
        'https://m.douban.com/',
        null,
      ]);
      expect(
        requests.every((request) => !request.headers.containsKey('cookie')),
        true,
      );
    },
  );
}

class FakePrivacy implements PrivacyRepository {
  final changes = ChangeNotifier();
  bool uncertain = false, failLoad = false;
  int saves = 0;
  Map<String, String>? lastEdits;
  Completer<ComposePrivacySettings>? pending;
  @override
  SessionScope get scope => session;
  @override
  Listenable get sessionChanges => changes;
  @override
  Future<ComposePrivacySettings> load() async {
    if (failLoad) throw const ApiException('privacyInvalid');
    return ComposePrivacySettings.fromJson(privacyJson(), session);
  }

  @override
  Future<ComposePrivacySettings> save(
    ComposePrivacySettings original,
    Map<String, String> edits,
  ) async {
    saves++;
    lastEdits = edits;
    if (pending != null) return pending!.future;
    if (uncertain) {
      throw const ApiException('privacyUnconfirmed', outcomeUnknown: true);
    }
    return ComposePrivacySettings.fromJson(privacyJson(edits), session);
  }
}
