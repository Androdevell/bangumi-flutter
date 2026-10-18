import 'dart:io';

import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/core/network/third_party_preview_service.dart';
import 'package:bangumi_flutter/core/network/safe_image_file_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';

void main() {
  test(
    'production safe image transport downloads Douban photos',
    () async {
      final service = ThirdPartyPreviewService(
        enabled: true,
        clientFactory:
            () => IOClient(HttpClient()..findProxy = (_) => 'DIRECT'),
      );
      addTearDown(service.dispose);
      final photos = await service.fetch(
        const Subject(
          id: 273,
          title: '千与千寻',
          originalTitle: '千と千尋の神隠し',
          type: 2,
          airDate: '2001-07-20',
        ),
      );
      expect(photos, isNotEmpty);
      final client = IOClient(HttpClient()..findProxy = (_) => 'DIRECT');
      addTearDown(client.close);
      final response = await SafeImageFileService(
        client,
      ).get(photos.first.imageUrl);
      expect(response.statusCode, 200);
      expect(
        (await response.content.expand((chunk) => chunk).toList()).length,
        greaterThan(0),
      );
    },
    skip:
        const bool.fromEnvironment('RUN_LIVE_PREVIEWS')
            ? false
            : 'Live third-party probe',
    timeout: const Timeout(Duration(seconds: 90)),
  );
  test(
    'Magic Explorer TV photos and image load through canonical redirect',
    () async {
      final service = ThirdPartyPreviewService(
        enabled: true,
        clientFactory:
            () => IOClient(HttpClient()..findProxy = (_) => 'DIRECT'),
      );
      addTearDown(service.dispose);
      final photos = await service.fetch(
        const Subject(
          id: 1,
          title: '魔法★探险家',
          originalTitle: 'マジカル★エクスプローラー',
          type: 2,
          airDate: '2026-01-01',
        ),
      );
      expect(photos, isNotEmpty);
      final client = IOClient(HttpClient()..findProxy = (_) => 'DIRECT');
      addTearDown(client.close);
      final response = await client
          .get(
            Uri.parse(photos.first.imageUrl),
            headers: {
              'Referer': 'https://m.douban.com/',
              'User-Agent': 'Mozilla/5.0',
            },
          )
          .timeout(const Duration(seconds: 12));
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], startsWith('image/'));
      expect(response.bodyBytes, isNotEmpty);
    },
    skip:
        const bool.fromEnvironment('RUN_LIVE_PREVIEWS')
            ? false
            : 'Live third-party probe',
    timeout: const Timeout(Duration(seconds: 90)),
  );
  test(
    'opt-in public Douban search, photos and image work without private keys',
    () async {
      final service = ThirdPartyPreviewService(
        enabled: true,
        clientFactory:
            () => IOClient(HttpClient()..findProxy = (_) => 'DIRECT'),
      );
      addTearDown(service.dispose);
      final photos = await service.fetch(
        const Subject(
          id: 273,
          title: '千与千寻',
          originalTitle: '千と千尋の神隠し',
          type: 2,
          airDate: '2001-07-20',
        ),
      );
      expect(photos, isNotEmpty);
      final client = IOClient(HttpClient()..findProxy = (_) => 'DIRECT');
      addTearDown(client.close);
      final response = await client
          .get(
            Uri.parse(photos.first.imageUrl),
            headers: const {
              'Referer': 'https://m.douban.com/',
              'User-Agent': 'Mozilla/5.0',
            },
          )
          .timeout(const Duration(seconds: 12));
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], startsWith('image/'));
      expect(response.bodyBytes, isNotEmpty);
    },
    skip:
        const bool.fromEnvironment('RUN_LIVE_PREVIEWS')
            ? false
            : 'Live third-party probe',
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
