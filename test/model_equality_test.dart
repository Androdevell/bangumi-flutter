import 'dart:io';

import 'package:bangumi_flutter/core/community_models.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/core/subject_detail_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归测试：三个「贴贴」tile 的 didUpdateWidget 改为值比较后，
/// 必须保证模型确实具备值语义，否则会退化成「永远不重置」。
void main() {
  group('SubjectComment', () {
    final json = <String, dynamic>{
      'id': 42,
      'user': {'username': 'alice', 'nickname': 'Alice'},
      'rate': 8,
      'comment': '好看',
      'updatedAt': '2026-10-01T00:00:00Z',
      'reactions': [
        {
          'value': '0',
          'total': 0,
          'users': [
            {'username': 'alice'},
            {'username': 'bob'},
          ],
        },
      ],
    };

    test('同一 JSON 解析两次应相等且哈希一致', () {
      final a = SubjectComment.fromJson(json);
      final b = SubjectComment.fromJson(json);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('集合字段的插入顺序不影响相等性', () {
      final a = SubjectComment.fromJson(json);
      final b = SubjectComment(
        id: a.id,
        userName: a.userName,
        username: a.username,
        avatarUrl: a.avatarUrl,
        rate: a.rate,
        comment: a.comment,
        updatedAt: a.updatedAt,
        reactionCount: a.reactionCount,
        reactedBy: a.reactedBy.toList().reversed.toSet(),
        reactions: {
          for (final key in a.reactions.keys.toList().reversed)
            key: a.reactions[key]!,
        },
        reactionUsers: {
          for (final key in a.reactionUsers.keys.toList().reversed)
            key: a.reactionUsers[key]!.toList().reversed.toSet(),
        },
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('贴贴用户变化必须破坏相等性', () {
      final a = SubjectComment.fromJson(json);
      final b = SubjectComment.fromJson({
        ...json,
        'reactions': [
          {
            'value': '0',
            'total': 0,
            'users': [
              {'username': 'alice'},
              {'username': 'carol'},
            ],
          },
        ],
      });
      expect(a, isNot(b));
    });
  });

  group('TimelineEntry', () {
    final json = <String, dynamic>{
      'id': 7,
      'cat': 3,
      'type': 10,
      'createdAt': 1789238400,
      'user': {'username': 'alice', 'nickname': 'Alice'},
      'memo': {
        'subject': [
          {
            'subject': {'id': 1, 'name_cn': '测试动画'},
          },
        ],
      },
      'reactions': [
        {
          'value': '0',
          'total': 1,
          'users': [
            {'username': 'alice'},
          ],
        },
      ],
    };

    test('同一 JSON 解析两次应相等', () {
      final a = TimelineEntry.fromJson(json);
      final b = TimelineEntry.fromJson(json);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('贴贴数量变化必须破坏相等性', () {
      final a = TimelineEntry.fromJson(json);
      final b = TimelineEntry.fromJson({
        ...json,
        'reactions': [
          {
            'value': '0',
            'total': 2,
            'users': [
              {'username': 'alice'},
              {'username': 'bob'},
            ],
          },
        ],
      });
      expect(a, isNot(b));
    });
  });

  group('CommunityReply', () {
    final json = <String, dynamic>{
      'id': 99,
      'content': 'reply',
      'state': 0,
      'createdAt': '2026-10-01T00:00:00Z',
      'user': {'id': 1, 'username': 'alice', 'nickname': 'Alice'},
      'reactions': [
        {
          'value': '0',
          'total': 1,
          'users': [
            {'username': 'bob'},
          ],
        },
      ],
      'replies': [
        {
          'id': 100,
          'content': 'nested',
          'state': 0,
          'user': {'id': 2, 'username': 'bob'},
        },
      ],
    };

    test('同一 JSON 解析两次应相等', () {
      final a = CommunityReply.fromJson(json);
      final b = CommunityReply.fromJson(json);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('嵌套回复变化必须破坏相等性（递归比较）', () {
      final a = CommunityReply.fromJson(json);
      final b = CommunityReply.fromJson({
        ...json,
        'replies': [
          {
            'id': 100,
            'content': 'nested changed',
            'state': 0,
            'user': {'id': 2, 'username': 'bob'},
          },
        ],
      });
      expect(a, isNot(b));
    });
  });

  group('调用点守卫', () {
    test('贴贴 tile 不应回退到 identical 判断', () {
      const files = [
        'lib/features/subject/subject_detail_page.dart',
        'lib/features/community/community_widgets.dart',
        'lib/features/timeline/timeline_page.dart',
      ];
      for (final path in files) {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('identical(oldWidget'),
          isFalse,
          reason: '$path 又用 identical 比较模型实例了，模型已有值语义，应使用 !=',
        );
      }
    });
  });
}
