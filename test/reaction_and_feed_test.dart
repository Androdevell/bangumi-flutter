import 'dart:convert';

import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/widgets/bangumi_rich_text.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bangumi smile and reaction ids resolve to the original assets', () {
    expect(
      bangumiEmojiUrl('bgm68'),
      'https://lain.bgm.tv/img/smiles/tv/45.gif',
    );
    expect(reactionImageUrl('54'), contains('/tv/15.gif'));
    expect(reactionImageUrl('140'), endsWith('/tv/101.png'));
  });

  test('reaction APIs submit a supported Bangumi reaction value', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('', 204);
    });
    final repository = RemoteBangumiRepository(
      apiClient: ApiClient(
        client: client,
        baseUri: Uri.parse('https://next.bgm.tv/'),
      ),
      externalClient: client,
    );

    await repository.setTimelineReaction(12, '54');
    await repository.setSubjectCommentReaction(34, '62');
    await repository.setEpisodeCommentReaction(56, null);
    await repository.setTopicPostReaction('group', 78, '79');

    expect(requests[0].method, 'PUT');
    expect(jsonDecode(requests[0].body), {'value': 54});
    expect(requests[1].url.path, '/p1/subjects/-/collects/34/like');
    expect(jsonDecode(requests[1].body), {'value': 62});
    expect(requests[2].method, 'DELETE');
    expect(requests[3].url.path, '/p1/groups/-/posts/78/like');
    expect(jsonDecode(requests[3].body), {'value': 79});
    repository.close();
  });

  test('timeline and rakuen models retain rich display metadata', () {
    final timeline = TimelineEntry.fromJson({
      'id': 1,
      'cat': 3,
      'type': 10,
      'createdAt': 1700000000,
      'source': {'name': 'web'},
      'replies': 3,
      'user': {'username': 'tester', 'nickname': 'Tester'},
      'memo': {
        'subject': [
          {
            'comment': '很好看',
            'subject': {
              'id': 42,
              'nameCN': '测试条目',
              'images': {'small': 'https://example.test/cover.jpg'},
            },
          },
        ],
      },
      'reactions': [
        {
          'value': '54',
          'total': 1,
          'users': [
            {'username': 'tester'},
          ],
        },
      ],
    });
    final topic = Topic.fromJson({
      'id': 9,
      'type': 'episode',
      'replyCount': 7,
      'updatedAt': 1700000000,
      'subject': {
        'id': 42,
        'nameCN': '测试条目',
        'images': {'small': 'https://example.test/cover.jpg'},
      },
      'episode': {'sort': 3, 'nameCN': '第三话'},
    });

    expect(timeline.imageUrl, contains('cover.jpg'));
    expect(timeline.detail, '很好看');
    expect(timeline.reactionBy('tester'), '54');
    expect(topic.subjectId, 42);
    expect(topic.title, contains('Ep.3'));
    expect(topic.typeLabel, '章节');
  });
}
