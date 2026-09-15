import 'dart:convert';

import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'repository sends the original search contract and parses its page',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 42,
                'name': 'Original',
                'name_cn': '搜索结果',
                'type': 2,
                'rating': {'score': 8.2, 'total': 99},
                'images': {'small': 'https://lain.bgm.tv/cover.jpg'},
              },
            ],
            'total': 1,
            'limit': 30,
            'offset': 0,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = RemoteBangumiRepository(
        apiClient: ApiClient(client: client),
      );

      final result = await repository.searchSubjects('测试', type: 2);

      expect(captured.url.path, '/p1/search/subjects');
      expect(captured.method, 'POST');
      expect(jsonDecode(captured.body), {
        'keyword': '测试',
        'filter': {
          'nsfw': true,
          'type': [2],
        },
        'sort': 'match',
      });
      expect(result.single.title, '搜索结果');
      expect(result.single.score, 8.2);
      repository.close();
    },
  );
}
