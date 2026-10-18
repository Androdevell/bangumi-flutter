import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/app/state/session_scope.dart';
import 'package:bangumi_flutter/core/localization/app_localizations.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/data/repositories/remote_account_settings_repository.dart';
import 'package:bangumi_flutter/domain/models/account_settings.dart';
import 'package:bangumi_flutter/domain/repositories/account_settings_repository.dart';
import 'package:bangumi_flutter/features/profile/editor/profile_editor_page.dart';
import 'comment_experience_test.dart' show host;
import 'community_extensions_test.dart'
    show authenticated, settingsHtml, session;

String emptyHashSettings({String nickname = 'Tester', String links = ''}) =>
    '${settingsHtml(nickname: nickname, formhash: '')}$links';

void main() {
  test('nonempty form token wins over links and cached session token', () {
    final result = parseAccountSettings(
      '${settingsHtml(formhash: 'form-token')}<a href="/erase/notify/all?gh=page-token">dismiss</a>',
      session,
      fallbackFormHash: 'cached-token',
    );
    expect(result.value('formhash'), 'form-token');
  });
  test(
    'cached token cannot turn an incomplete form into a writable profile',
    () {
      expect(
        () => parseAccountSettings(
          '<form><input name="nickname" value="Tester"></form>',
          session,
          fallbackFormHash: 'cached-token',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'profileFormInvalid',
          ),
        ),
      );
    },
  );
  test(
    'foreign settings redirect never confirms or repeats a profile write',
    () async {
      var calls = 0;
      final (api, auth) = await authenticated(
        MockClient((request) async {
          calls++;
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://example.com/settings'},
          );
        }),
      );
      await expectLater(
        api.accountSettings(
          scope: api.sessionScope,
          fields: {'nickname': 'Tester'},
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.outcomeUnknown,
            'unknown',
            isTrue,
          ),
        ),
      );
      expect(calls, 1);
      api.close();
      auth.dispose();
    },
  );
  for (final (status, message) in [
    (403, 'profileWebUnavailable'),
    (429, 'profileRateLimited'),
    (503, 'profileLoadFailed'),
  ]) {
    test('settings HTTP $status has an actionable error', () async {
      final (api, auth) = await authenticated(
        MockClient((_) async => http.Response('error', status)),
      );
      await expectLater(
        api.accountSettings(scope: api.sessionScope),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', message),
        ),
      );
      api.close();
      auth.dispose();
    });
  }
  test('empty HTML formhash uses the current same-site page hash', () {
    final result = parseAccountSettings(
      emptyHashSettings(
        links: '<a href="/erase/notify/all?gh=page-hash">dismiss</a>',
      ),
      session,
    );
    expect(result.value('formhash'), 'page-hash');
    expect(result.value('nickname'), 'Tester');
  });
  test(
    'external and conflicting page hash candidates cannot authorize a form',
    () {
      for (final links in [
        '<a href="https://example.com/erase/notify/all?gh=foreign">link</a>',
        '<a href="javascript:ignoreUser(1,2,3)">link</a>',
        '<a href="/erase/notify/all?gh=one">1</a><a href="/logout?gh=two">2</a>',
      ]) {
        expect(
          () => parseAccountSettings(emptyHashSettings(links: links), session),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );
  test(
    'complete empty-hash profile uses account session hash and saves once',
    () async {
      var name = 'Tester';
      var posts = 0;
      final (api, auth) = await authenticated(
        MockClient((request) async {
          if (request.method == 'POST') {
            posts++;
            expect(request.body, contains('name="formhash"\r\n\r\ncsrf'));
            expect(request.body, contains('name="keep"\r\n\r\nuntouched'));
            expect(request.body, isNot(contains('name="email"')));
            name = 'Updated';
            return http.Response('', 303, headers: {'location': '/settings'});
          }
          return http.Response.bytes(
            utf8.encode(emptyHashSettings(nickname: name)),
            200,
          );
        }),
      );
      final repo = RemoteAccountSettingsRepository(api, onChanged: () {});
      final original = await repo.load();
      expect(original.value('formhash'), 'csrf');
      final confirmed = await repo.save(original, {'nickname': 'Updated'});
      expect(confirmed.value('nickname'), 'Updated');
      expect(posts, 1);
      api.close();
      auth.dispose();
    },
  );
  test(
    'settings login redirect is reported as web session expiration',
    () async {
      final (api, auth) = await authenticated(
        MockClient(
          (_) async => http.Response(
            '',
            302,
            headers: {'location': '/login?backTo=%2Fsettings'},
          ),
        ),
      );
      await expectLater(
        api.accountSettings(scope: api.sessionScope),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'profileWebLoginRequired',
          ),
        ),
      );
      api.close();
      auth.dispose();
    },
  );
  for (final locale in ['zh', 'en', 'ja']) {
    testWidgets(
      'initial profile errors are localized instead of raw keys in $locale',
      (tester) async {
        final repo = _FailedSettings();
        final strings = AppLocalizations(Locale(locale));
        await tester.pumpWidget(
          host(ProfileEditorPage(repository: repo), locale: locale),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(strings.t('profileFormInvalid')),
          findsOneWidget,
        );
        expect(find.text('profileFormInvalid'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        repo.changes.dispose();
      },
    );
  }
}

class _FailedSettings implements AccountSettingsRepository {
  final changes = ChangeNotifier();
  @override
  SessionScope get scope => session;
  @override
  Listenable get sessionChanges => changes;
  @override
  Future<ComposeAccountSettings> load() async =>
      throw const ApiException('profileFormInvalid');
  @override
  Future<ComposeAccountSettings> save(
    ComposeAccountSettings original,
    Map<String, String> edits, {
    Uint8List? avatar,
  }) => throw UnimplementedError();
}
