import 'dart:io';

import 'package:bangumi_flutter/core/network/platform_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Windows native transport reaches Bangumi through system settings',
    () async {
      if (!Platform.isWindows) return;
      final client = createPlatformHttpClient();
      try {
        final response = await client
            .get(Uri.parse('https://next.bgm.tv/p1/calendar'))
            .timeout(const Duration(seconds: 25));
        expect(response.statusCode, 200);
        expect(response.body, isNotEmpty);
      } finally {
        client.close();
      }
    },
    skip: 'Live network probe',
  );
}
