import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source build number exceeds the actual last published APK 2006', () {
    final match = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(match, isNotNull);
    expect(int.parse(match!.group(2)!), greaterThan(2006));
  });
  test(
    'official packaging rejects missing OAuth, stale version and mismatched signer',
    () {
      final script = File('tool/release.ps1').readAsStringSync();
      expect(script, contains('IsNullOrWhiteSpace(\$clientId)'));
      expect(script, contains('IsNullOrWhiteSpace(\$clientSecret)'));
      expect(script, contains('\$code -le \$previous.Code'));
      expect(script, contains('\$fingerprint -ne (Read-Certificate'));
      expect(script, contains('--target-platform android-arm64'));
      expect(script, contains('ProductVersion -ne'));
    },
  );
  test(
    'Android release independently refuses unconfigured or downgrade builds',
    () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('flutter.versionCode <= 2006'));
      expect(gradle, contains('defines["BGM_OAUTH_APP_ID"].isNullOrBlank()'));
      expect(
        gradle,
        contains('defines["BGM_OAUTH_APP_SECRET"].isNullOrBlank()'),
      );
      expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    },
  );
}
