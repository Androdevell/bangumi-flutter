import 'dart:async';

import 'package:bangumi_flutter/core/community_models.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/features/community/community_widgets.dart';
import 'package:bangumi_flutter/features/community/reaction_picker.dart';
import 'package:bangumi_flutter/features/timeline/timeline_page.dart';
import 'package:bangumi_flutter/widgets/bangumi_rich_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CommunityReply _reply(int id, String value, int count, {String user = 'me'}) =>
    CommunityReply.fromJson({
      'id': id,
      'content': 'reply-$id',
      'user': {'username': 'author-$id'},
      'reactions': [
        {
          'value': value,
          'total': count,
          'users': [
            {'username': user},
          ],
        },
      ],
    });

Widget _replies(
  List<CommunityReply> items, {
  String account = 'me',
  Future<void> Function(CommunityReply, String?)? onLike,
}) => MaterialApp(
  home: Scaffold(
    body: CommunityReplyList(
      items: items,
      currentUsername: account,
      onUserTap: (_) {},
      onLike: onLike ?? (_, __) async {},
    ),
  ),
);

void _expectReaction(
  WidgetTester tester,
  String key,
  String value,
  int count, {
  bool selected = true,
}) {
  final tile = find.byKey(ValueKey(key));
  expect(tile, findsOneWidget);
  final summary = tester.widget<ReactionSummary>(
    find.descendant(of: tile, matching: find.byType(ReactionSummary)),
  );
  expect(summary.reactions, {value: count});
  final button = tester.widget<IconButton>(
    find.descendant(of: tile, matching: find.byType(IconButton)),
  );
  if (selected) {
    expect(button.icon, isA<BangumiReactionImage>());
    expect((button.icon as BangumiReactionImage).value, value);
  } else {
    expect(button.icon, isA<Icon>());
  }
}

void main() {
  testWidgets('reply states follow IDs when [A,B] becomes [B,C]', (
    tester,
  ) async {
    final a = _reply(1, '54', 2);
    final b = _reply(2, '62', 4);
    final c = _reply(3, '79', 6);
    await tester.pumpWidget(_replies([a, b]));
    _expectReaction(tester, 'reply:1:me', '54', 2);
    _expectReaction(tester, 'reply:2:me', '62', 4);
    await tester.pumpWidget(_replies([b, c]));
    expect(find.byKey(const ValueKey('reply:1:me')), findsNothing);
    _expectReaction(tester, 'reply:2:me', '62', 4);
    _expectReaction(tester, 'reply:3:me', '79', 6);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('same ID refresh and account switch resync reaction snapshots', (
    tester,
  ) async {
    await tester.pumpWidget(_replies([_reply(2, '62', 4)]));
    await tester.pumpWidget(_replies([_reply(2, '79', 8)]));
    _expectReaction(tester, 'reply:2:me', '79', 8);
    await tester.pumpWidget(_replies([_reply(2, '79', 8)], account: 'other'));
    _expectReaction(tester, 'reply:2:other', '79', 8, selected: false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stale in-flight reaction cannot overwrite a refreshed item', (
    tester,
  ) async {
    final started = Completer<void>();
    final response = Completer<void>();
    Future<void> onLike(CommunityReply item, String? value) {
      expect(item.id, 2);
      expect(value, '79');
      started.complete();
      return response.future;
    }

    await tester.pumpWidget(_replies([_reply(2, '62', 4)], onLike: onLike));
    await tester.tap(find.byTooltip('更换表情'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('79'));
    await tester.pumpAndSettle();
    expect(started.isCompleted, isTrue);
    await tester.pumpWidget(_replies([_reply(2, '54', 10)], onLike: onLike));
    response.complete();
    await tester.pump();
    _expectReaction(tester, 'reply:2:me', '54', 10);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'timeline refresh keeps IDs, refreshed counts and account selection',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _TimelineRepository();
      final app = MaterialApp(
        home: Scaffold(body: TimelinePage(repository: repo)),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      _expectReaction(tester, 'timeline:1:me', '54', 2);
      _expectReaction(tester, 'timeline:2:me', '62', 4);
      repo.entries = [_entry(2, '79', 8), _entry(3, '80', 6)];
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('timeline:1:me')), findsNothing);
      _expectReaction(tester, 'timeline:2:me', '79', 8);
      _expectReaction(tester, 'timeline:3:me', '80', 6);
      repo.currentUsername = 'other';
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      _expectReaction(tester, 'timeline:2:other', '79', 8, selected: false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

TimelineEntry _entry(int id, String value, int count) => TimelineEntry(
  id: id,
  user: 'author-$id',
  username: 'author-$id',
  action: 'updated',
  subject: 'subject-$id',
  createdAt: DateTime(2026),
  reactions: {value: count},
  reactionUsers: {
    value: {'me'},
  },
);

class _TimelineRepository implements BangumiRepository {
  List<TimelineEntry> entries = [_entry(1, '54', 2), _entry(2, '62', 4)];

  @override
  String currentUsername = 'me';

  @override
  bool get isLoggedIn => true;

  @override
  Future<List<TimelineEntry>> fetchTimeline({
    String mode = 'all',
    int? category,
  }) async => entries;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
