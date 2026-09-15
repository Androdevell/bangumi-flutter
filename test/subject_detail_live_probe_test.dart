import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/core/network/platform_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _runLiveTests = bool.fromEnvironment('RUN_LIVE_BGM_TESTS');

void main() {
  test(
    'subject detail sections match the live APIs',
    () async {
      final repository = RemoteBangumiRepository();
      addTearDown(repository.close);

      final details = await repository.fetchSubjectDetails(485);

      expect(details.subject.title, isNotEmpty);
      expect(details.episodes, isNotEmpty);
      expect(details.previews, isNotEmpty);
      expect(details.comments, isNotEmpty);
      expect(details.characters, isNotEmpty);
      expect(details.staffs, isNotEmpty);
      expect(details.relations, isNotEmpty);
      expect(details.indexes, isNotEmpty);
      expect(details.reviews, isNotEmpty);
      expect(details.topics, isNotEmpty);
      expect(details.ratingDistribution, hasLength(10));
      expect(details.collectionCounts, isNotEmpty);

      final imageClient = createPlatformHttpClient();
      addTearDown(imageClient.close);
      var loaded = 0;
      for (final preview in details.previews.take(12)) {
        for (final url in {preview.imageUrl, preview.largeImageUrl}) {
          try {
            final response = await imageClient
                .get(
                  Uri.parse(url),
                  headers: const {
                    'User-Agent':
                        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                        'Chrome/131.0 Mobile Safari/537.36',
                    'Referer': 'https://movie.douban.com/',
                  },
                )
                .timeout(const Duration(seconds: 12));
            if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
              loaded++;
              break;
            }
          } on Object {
            // The alternate URL is checked below.
          }
        }
      }
      expect(
        loaded,
        greaterThanOrEqualTo(details.previews.take(12).length - 1),
      );
    },
    skip: _runLiveTests ? false : 'Live network probe',
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
