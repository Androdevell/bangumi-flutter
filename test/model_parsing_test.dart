import 'package:bangumi_flutter/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses subject response used by next.bgm.tv', () {
    final subject = Subject.fromJson({
      'id': 485936,
      'name': 'Test Original',
      'name_cn': '测试条目',
      'type': 2,
      'eps': 12,
      'summary': '简介',
      'airtime': {'date': '2026-09-13'},
      'images': {'large': 'https://lain.bgm.tv/test.jpg'},
      'rating': {'score': 8.7, 'total': 1234, 'rank': 42},
    });

    expect(subject.id, 485936);
    expect(subject.title, '测试条目');
    expect(subject.imageUrl, 'https://lain.bgm.tv/test.jpg');
    expect(subject.score, 8.7);
    expect(subject.ratingCount, 1234);
  });

  test('parses timeline subject activity', () {
    final entry = TimelineEntry.fromJson({
      'id': 12,
      'cat': 3,
      'type': 10,
      'createdAt': 1789238400,
      'user': {'nickname': 'hana7'},
      'memo': {
        'subject': [
          {
            'subject': {'id': 485936, 'name_cn': '测试动画'},
          },
        ],
      },
    });

    expect(entry.user, 'hana7');
    expect(entry.action, '在看');
    expect(entry.subject, '测试动画');
    expect(entry.subjectId, 485936);
  });
}
