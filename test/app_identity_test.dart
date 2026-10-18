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
    expect(browserUserAgent, endsWith(appUserAgent));
  });
}
