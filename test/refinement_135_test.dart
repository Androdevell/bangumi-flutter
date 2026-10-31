import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bangumi_flutter/core/paged.dart';
import 'package:bangumi_flutter/core/paged_controller.dart';
import 'package:bangumi_flutter/core/network/read_task_scope.dart';
import 'package:bangumi_flutter/widgets/lazy_tab_view.dart';
import 'package:bangumi_flutter/core/localization/refinement_strings.dart';

void main() {
  test('duplicate middle page does not hide following items', () async {
    final controller = PagedController<int>(
      load:
          (cursor) async => Paged(
            items: [cursor < 2 ? 1 : 2],
            offset: cursor,
            limit: 1,
            total: 3,
          ),
      idOf: (id) => id,
    );
    await controller.loadMore();
    await controller.loadMore();
    expect(controller.hasMore, true);
    await controller.loadMore();
    expect(controller.items, [1, 2]);
    controller.dispose();
  });
  test('endless duplicate pages stop at the safety budget', () async {
    var calls = 0;
    final controller = PagedController<int>(
      load: (cursor) async {
        calls++;
        return Paged(
          items: [1],
          offset: cursor,
          limit: 1,
          hasMoreOverride: true,
        );
      },
      idOf: (id) => id,
    );
    for (var i = 0; i < 10; i++) {
      await controller.loadMore();
    }
    expect(calls, 4);
    expect(controller.hasMore, false);
    controller.dispose();
  });
  testWidgets(
    'section retry cancels previous scope and removal cancels new scope',
    (tester) async {
      final scopes = <ReadTaskScope>[];
      var fail = true;
      Future<int> load() {
        scopes.add(ReadTaskScope.current!);
        return fail
            ? Future.error(StateError('fixture'))
            : Completer<int>().future;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SectionLoader<int>(
              load: load,
              builder: (value) => Text('$value'),
            ),
          ),
        ),
      );
      await tester.pump();
      fail = false;
      final button = find.byType(FilledButton);
      // Error view exposes a retry button through its localized label.
      if (button.evaluate().isNotEmpty) {
        await tester.tap(button.first);
      } else {
        await tester.tap(find.text('重试').first);
      }
      await tester.pump();
      expect(scopes.length, 2);
      expect(scopes.first.isCancelled, true);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(scopes.last.isCancelled, true);
    },
  );
  test('all refinement translations have identical complete keys', () {
    final keys = refinementStrings['zh']!.keys.toSet();
    for (final lang in ['en', 'ja']) {
      expect(refinementStrings[lang]!.keys.toSet(), keys);
      expect(refinementStrings[lang]!.values.every((v) => v.isNotEmpty), true);
    }
  });
}
