import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/localization/app_localizations.dart';
import 'package:bangumi_flutter/core/media/rich_image_policy.dart';
import 'package:bangumi_flutter/core/network/third_party_preview_service.dart';
import 'package:bangumi_flutter/widgets/common.dart';
import 'package:bangumi_flutter/widgets/rich_comment_image.dart';
import 'package:bangumi_flutter/widgets/third_party_preview_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'comment_experience_test.dart' show host;

void main() {
  for (final locale in ['zh', 'en', 'ja']) {
    testWidgets(
      'comment image setting restores separately from profile scroll in $locale',
      (tester) async {
        await RichImagePolicy.instance.initialize(MemorySecureVault());
        final bucket = PageStorageBucket();
        final service = ThirdPartyPreviewService();
        final strings = AppLocalizations(Locale(locale));
        Widget page() => host(
          Scaffold(
            body: PageStorage(
              bucket: bucket,
              child: ListView(
                key: const PageStorageKey('profile-scroll'),
                children: [
                  const SizedBox(height: 500),
                  SurfaceBlock(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ThirdPartyPreviewSetting(service: service),
                        const CommentImageSetting(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 800),
                ],
              ),
            ),
          ),
          locale: locale,
        );
        await tester.pumpWidget(page());
        await tester.scrollUntilVisible(
          find.text(strings.t('commentImages')),
          250,
        );
        await tester.pumpAndSettle();
        final before =
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .pixels;
        expect(before, greaterThan(0));
        await tester.pumpWidget(host(const SizedBox()));
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(find.text(strings.t('commentImages')), findsOneWidget);
        expect(
          tester.getSize(find.byType(CommentImageSetting)).height,
          lessThan(100),
        );
        await tester.tap(find.text(strings.t('commentImages')));
        await tester.pumpAndSettle();
        await tester.pumpWidget(host(const SizedBox()));
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(find.text(strings.t('imageOnDemand')), findsOneWidget);
        final after =
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .pixels;
        expect(after, before);
        await tester.pumpWidget(const SizedBox());
        service.dispose();
      },
    );
  }
}
