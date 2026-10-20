import 'dart:io';
import 'package:bangumi_flutter/core/app_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('network identity matches the package release version', () {
    final version = RegExp(
      r'^version: (\d+\.\d+\.\d+)\+',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(appVersion, version);
    expect(appUserAgent, 'BangumiFlutter/$version');
    // 网页认证标识独立于应用发布版本，不能在升级时改变。
    expect(browserUserAgent, endsWith('BangumiFlutter/1.2.8'));
  });
}
