import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/cache/calendar_snapshot.dart';
import 'package:bangumi_flutter/core/cache/public_calendar_vault.dart';

void main() {
  test(
    'public cache migrates reads and never writes credentials to ordinary files',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bangumi-public-calendar-test-',
      );
      addTearDown(() async {
        expect(root.absolute.path, contains('bangumi-public-calendar-test-'));
        await root.delete(recursive: true);
      });
      final legacy = MemorySecureVault();
      final old = CalendarSnapshotStore(legacy, 'https://next.bgm.tv/');
      await old.write({'Mon': []});
      final storage = PublicCalendarVault(legacy, directory: () async => root);
      final current = CalendarSnapshotStore(storage, 'https://next.bgm.tv/');
      expect((await current.read())?.data, {'Mon': []});
      await current.write({'Tue': []});
      expect((await current.read())?.data, {'Tue': []});
      expect((await old.read())?.data, {'Mon': []});
      await expectLater(
        storage.write('bangumi.auth.session.v2', 'secret'),
        throwsArgumentError,
      );
      final files =
          await root.list().where((e) => e.path.endsWith('.json')).toList();
      expect(files.length, 1);
      expect(
        await File(files.single.path).readAsString(),
        isNot(contains('secret')),
      );
      expect(
        await CalendarSnapshotStore(storage, 'https://other.example/').read(),
        isNull,
      );
    },
  );
}
