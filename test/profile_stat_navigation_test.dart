import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/core/localization/app_localizations.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/features/user/user_profile_page.dart';
import 'package:bangumi_flutter/widgets/bangumi_rich_text.dart';
import 'collection_architecture_test.dart' show MutableSessionApi;
import 'comment_experience_test.dart' show host;

void main() {
  testWidgets(
    'profile cards select tabs and replace already visited collection filters',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final queries = <Map<String, String>>[];
      final paths = <String>[];
      final repository = RemoteBangumiRepository(
        apiClient: MutableSessionApi(
          MockClient((request) async {
            paths.add(request.url.path);
            Object data = {'data': [], 'total': 0};
            if (request.url.path == '/p1/users/tester') {
              data = {
                'id': 7,
                'username': 'tester',
                'nickname': 'Tester',
                'bio': '[color=red]Hello[/color]',
                'stats': {
                  'subject': {
                    '2': {'2': 5},
                    '1': {'2': 3},
                  },
                },
              };
            } else if (request.url.path == '/p1/collections/subjects') {
              queries.add(Map.of(request.url.queryParameters));
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
      await tester.pumpWidget(
        host(UserProfilePage(username: 'tester', repository: repository)),
      );
      await tester.pumpAndSettle();
      final strings = AppLocalizations(const Locale('zh'));
      await tester.tap(
        find.widgetWithText(FilterChip, strings.t('originalColors')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<BangumiRichText>(find.byType(BangumiRichText))
            .any((widget) => widget.originalColors),
        true,
      );
      await tester.tap(find.byKey(const ValueKey('profile-stat-看过')));
      await tester.pumpAndSettle();
      expect(queries.last['type'], '2');
      expect(queries.last.containsKey('subjectType'), false);
      await tester.tap(find.widgetWithText(ChoiceChip, strings.t('mediaBook')));
      await tester.pumpAndSettle();
      expect(queries.last['subjectType'], '1');
      await tester.tap(find.widgetWithText(Tab, '时光机'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-stat-收藏')));
      await tester.pumpAndSettle();
      expect(
        find
            .widgetWithText(ChoiceChip, strings.t('allMedia'))
            .evaluate()
            .single
            .widget,
        isA<ChoiceChip>().having((w) => w.selected, 'selected', true),
      );
      expect(
        tester
            .widget<FilterChip>(
              find.widgetWithText(FilterChip, strings.t('allStatuses')),
            )
            .selected,
        true,
      );
      await tester.tap(find.widgetWithText(Tab, '时光机'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-stat-日志')));
      await tester.pumpAndSettle();
      expect(find.text('暂无日志'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, '时光机'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-stat-好友')));
      await tester.pumpAndSettle();
      expect(find.text('暂无公开好友'), findsOneWidget);
      expect(paths.where((path) => path == '/p1/users/tester').length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
