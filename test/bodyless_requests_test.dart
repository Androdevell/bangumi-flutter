import 'dart:convert';
import 'dart:io';

import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('add and remove friend omit content type for bodyless requests', () async {
    final requests = <http.Request>[];
    final repo = RemoteBangumiRepository(
      apiClient: ApiClient(
        client: MockClient((request) async {
          requests.add(request);
          // 服务端会拒绝带 JSON 类型的空请求体，尚未进入好友处理器。
          if (request.body.isEmpty &&
              request.headers['content-type']?.contains('application/json') ==
                  true) {
            return http.Response(
              '{"message":"Body cannot be empty when content-type is set to application/json"}',
              400,
            );
          }
          return http.Response('{}', 200);
        }),
      ),
    );
    addTearDown(repo.close);
    await repo.toggleFriend('friend_name', false);
    await repo.toggleFriend('friend_name', true);
    expect(requests.map((r) => r.method), ['PUT', 'DELETE']);
    for (final request in requests) {
      expect(request.url.path, '/p1/friends/friend_name');
      expect(request.bodyBytes, isEmpty);
      expect(request.headers.containsKey(HttpHeaders.contentTypeHeader), false);
    }
  });

  for (final method in ['POST', 'PUT', 'PATCH', 'DELETE']) {
    test('$method with body retains JSON content type and encoding', () async {
      final api = ApiClient(
        client: MockClient((request) async {
          expect(
            request.headers['content-type'],
            'application/json; charset=utf-8',
          );
          expect(jsonDecode(request.body), {'content': '测试内容'});
          return http.Response('{}', 200);
        }),
      );
      addTearDown(api.close);
      const body = {'content': '测试内容'};
      switch (method) {
        case 'POST':
          await api.post('test', body: body);
        case 'PUT':
          await api.put('test', body: body);
        case 'PATCH':
          await api.patch('test', body: body);
        case 'DELETE':
          await api.delete('test', body: body);
      }
    });
  }
}
