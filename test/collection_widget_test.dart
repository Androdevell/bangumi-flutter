import 'dart:convert';
import 'package:bangumi_flutter/core/localization/app_localizations.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/features/user/user_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'collection_architecture_test.dart' show MutableSessionApi;

void main() {
  for (final locale in ['zh', 'en', 'ja']) {
    testWidgets(
      'collection filter is remote, localized and retains pagination in $locale',
      (tester) async {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final queries = <Map<String, String>>[];
        final repository = RemoteBangumiRepository(
          apiClient: MutableSessionApi(
            MockClient((request) async {
              Object data = {'data': []};
              if (request.url.path == '/p1/users/tester') {
                data = {
                  'id': 7,
                  'username': 'tester',
                  'nickname': 'Tester',
                  'stats': {
                    'subject': {
                      '2': {'2': 120},
                    },
                  },
                };
              } else if (request.url.path == '/p1/collections/subjects') {
                final query = request.url.queryParameters;
                queries.add(query);
                final offset = int.parse(query['offset']!);
                data = {
                  'data': [
                    for (var i = offset; i < offset + 40 && i < 81; i++)
                      {
                        'id': i + 1,
                        'nameCN': 'item $i',
                        'type': int.parse(query['subjectType'] ?? '2'),
                        'interest': {'type': 3, 'rate': 8},
                      },
                  ],
                  'total': 81,
                };
              }
              return http.Response(
                jsonEncode(data),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        );
        addTearDown(repository.close);
        final strings = AppLocalizations(Locale(locale));
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: UserProfilePage(
              username: 'tester',
              repository: repository,
              initialIndex: 1,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(queries.last, {'limit': '40', 'offset': '0'});
        await tester.tap(
          find.widgetWithText(ChoiceChip, strings.t('mediaBook')),
        );
        await tester.pumpAndSettle();
        expect(queries.last['subjectType'], '1');
        expect(queries.last['offset'], '0');
        await tester.tap(find.text(strings.t('loadMore')));
        await tester.pumpAndSettle();
        expect(queries.last['offset'], '40');
        expect(queries.last['subjectType'], '1');
        await tester.tap(find.text(strings.t('loadMore')));
        await tester.pumpAndSettle();
        expect(queries.last['offset'], '80');
        expect(find.text(strings.t('loadMore')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
