import 'dart:convert';

import 'package:bangumi_flutter/core/localization/app_localizations.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/core/network/third_party_preview_service.dart';
import 'package:bangumi_flutter/features/subject/subject_preview_panel.dart';
import 'package:bangumi_flutter/widgets/third_party_preview_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget host(Widget child, {String locale = 'zh'}) => MaterialApp(
  locale: Locale(locale),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);
const subject = Subject(id: 273, title: '千与千寻', type: 2, airDate: '2001');

void main() {
  testWidgets(
    'consent cancel stays off, confirm enables, disable skips dialog',
    (tester) async {
      final service = ThirdPartyPreviewService();
      await tester.pumpWidget(host(ThirdPartyPreviewSetting(service: service)));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.textContaining('作品标题'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(service.enabled, false);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('允许并开启'));
      await tester.pumpAndSettle();
      expect(service.enabled, true);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(service.enabled, false);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );

  testWidgets(
    'prebuilt inactive preview tab never sends titles, selecting it does',
    (tester) async {
      var calls = 0;
      final service = ThirdPartyPreviewService(
        enabled: true,
        clientFactory:
            () => MockClient((r) async {
              calls++;
              return http.Response(jsonEncode([]), 200);
            }),
      );
      await tester.pumpWidget(
        host(
          DefaultTabController(
            length: 3,
            child: Column(
              children: [
                const TabBar(
                  tabs: [Tab(text: '简介'), Tab(text: '章节'), Tab(text: '预览')],
                ),
                // 始终构建组件，证明不会仅因预加载/构建而外发。
                Expanded(
                  child: SubjectPreviewPanel(
                    subject: subject,
                    service: service,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(calls, 0);
      await tester.tap(find.text('预览'));
      await tester.pumpAndSettle();
      expect(
        DefaultTabController.of(
          tester.element(find.byType(SubjectPreviewPanel)),
        ).index,
        2,
      );
      expect(calls, 1);
      expect(find.textContaining('没有找到'), findsOneWidget);
      await service.setEnabled(false);
      await tester.pumpAndSettle();
      expect(find.textContaining('第三方剧照默认关闭'), findsOneWidget);
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );

  testWidgets(
    'blocked provider is distinguished from an empty match and retry works',
    (tester) async {
      var calls = 0;
      final service = ThirdPartyPreviewService(
        enabled: true,
        clientFactory:
            () => MockClient((r) async {
              calls++;
              return http.Response('blocked', 403);
            }),
      );
      await tester.pumpWidget(
        host(SubjectPreviewPanel(subject: subject, service: service)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('需要网页验证'), findsOneWidget);
      expect(find.textContaining('没有找到'), findsNothing);
      await tester.tap(find.byTooltip('重试'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );

  for (final language in ['zh', 'en', 'ja']) {
    testWidgets('preview consent and switch are localized in $language', (
      tester,
    ) async {
      final service = ThirdPartyPreviewService();
      final strings = AppLocalizations(Locale(language));
      await tester.pumpWidget(
        host(ThirdPartyPreviewSetting(service: service), locale: language),
      );
      expect(find.text(strings.t('thirdPartyPreviews')), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(strings.t('previewConsent')), findsOneWidget);
      await tester.tap(find.text(strings.t('cancel')));
      await tester.pumpAndSettle();
      expect(service.enabled, false);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    });
  }
}
