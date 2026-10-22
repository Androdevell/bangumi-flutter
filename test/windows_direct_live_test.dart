import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bangumi_flutter/core/network/windows_direct_client.dart';
import 'package:bangumi_flutter/core/network/image_transport.dart';
import 'package:bangumi_flutter/core/network/safe_image_file_service.dart';
import 'package:bangumi_flutter/core/models.dart';

void main() {
  test(
    'Windows direct API and image probe (explicit opt-in)',
    () async {
      final client = createWindowsDirectClient();
      String? cover;
      addTearDown(client.close);
      for (final url in [
        'https://next.bgm.tv/p1/calendar',
        'https://lain.bgm.tv/pic/photo/l/19/57/138463_iJH12.jpg',
      ]) {
        final clock = Stopwatch()..start();
        final response = await client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 25));
        // ignore: avoid_print
        print(
          '${Uri.parse(url).host}: ${response.statusCode}, ${response.bodyBytes.length} bytes, ${clock.elapsedMilliseconds} ms',
        );
        expect(response.statusCode, 200);
        expect(response.bodyBytes, isNotEmpty);
        if (Uri.parse(url).host == 'next.bgm.tv') {
          final data = jsonDecode(response.body) as Map;
          final wrapper = (data.values.first as List).first as Map;
          // ignore: avoid_print
          print('calendar keys: ${data.keys}; item keys: ${wrapper.keys}');
          final first =
              wrapper['subject'] is Map ? wrapper['subject'] as Map : wrapper;
          cover = Subject.fromJson(Map<String, dynamic>.from(first)).imageUrl;
          // ignore: avoid_print
          print('calendar image: $cover');
        }
      }
      final images = ImageTransport(createWindowsDirectClient());
      addTearDown(images.close);
      // ignore: avoid_print
      print('image DNS: ${await InternetAddress.lookup('lain.bgm.tv')}');
      final response = await SafeImageFileService(
        images,
      ).get('https://lain.bgm.tv/pic/photo/l/19/57/138463_iJH12.jpg');
      expect(response.statusCode, 200);
      expect(await response.content.expand((v) => v).length, greaterThan(0));
      final poster = await SafeImageFileService(images).get(cover!);
      expect(poster.statusCode, 200);
      expect(await poster.content.expand((v) => v).length, greaterThan(0));
    },
    skip:
        !Platform.isWindows || Platform.environment['BGM_LIVE_NETWORK'] != '1',
  );
}
