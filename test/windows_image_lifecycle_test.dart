import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/core/diagnostics/image_diagnostics.dart';
import 'package:bangumi_flutter/core/network/image_transfer_files.dart';
import 'package:bangumi_flutter/core/network/safe_image_file_service.dart';
import 'package:bangumi_flutter/core/network/image_header.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
);

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bgm-owned-transfer-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'concurrent release is idempotent and cannot delete a neighboring transfer',
    () async {
      final diagnostics = ImageDiagnostics(enabled: true);
      final files = ImageTransferFiles(directory: root);
      final transfers = await Future.wait(
        List.generate(8, (_) => files.create(diagnostics: diagnostics)),
      );
      for (final transfer in transfers) {
        await transfer.file.writeAsBytes(png);
      }
      await Future.wait(List.generate(10, (_) => transfers.first.release()));
      expect(await transfers.first.file.parent.exists(), false);
      for (final transfer in transfers.skip(1)) {
        expect(await transfer.file.readAsBytes(), png);
        await transfer.release();
      }
      final counts = diagnostics.snapshot['counts'] as Map;
      expect(counts['cleanupStarted'], 8);
      expect(counts['cleanupFinished'], 8);
      expect(counts['cleanupRepeated'], 9);
    },
  );

  test(
    'interrupted body preserves the original exception and releases its directory',
    () async {
      final files = ImageTransferFiles(directory: root);
      final transfer = await files.create();
      final error = HttpException('fixture interruption');
      Stream<List<int>> stream() async* {
        yield png;
        throw error;
      }

      await expectLater(
        transfer.prepare(stream(), (_) async {}),
        throwsA(same(error)),
      );
      expect(await transfer.file.parent.exists(), false);
    },
  );

  test('cancelling content completes cleanup before cancel returns', () async {
    final transfer = await ImageTransferFiles(directory: root).create();
    await transfer.prepare(
      Stream.value(List<int>.filled(256 * 1024, 0)),
      (_) async {},
    );
    final first = Completer<void>();
    final subscription = transfer.read().listen((_) {
      if (!first.isCompleted) first.complete();
    });
    await first.future;
    await subscription.cancel();
    expect(await transfer.file.parent.exists(), false);
  });

  test(
    'invalid image cooldown expires and explicit retry bypasses it',
    () async {
      var now = DateTime(2026, 10, 26);
      var calls = 0;
      final service = SafeImageFileService(
        MockClient((_) async {
          calls++;
          return http.Response.bytes(List.filled(128, 0), 200);
        }),
        files: ImageTransferFiles(directory: root),
        clock: () => now,
        lookup: (_) async => [InternetAddress('8.8.8.8')],
      );
      const url = 'https://lain.bgm.tv/fixture';
      Future<void> fail() async =>
          expectLater(service.get(url), throwsA(isA<HttpException>()));
      await fail();
      await fail();
      expect(calls, 1);
      service.clearFailure(url);
      await fail();
      expect(calls, 2);
      now = now.add(const Duration(seconds: 31));
      await fail();
      expect(calls, 3);
      expect(await root.list().toList(), isEmpty);
    },
  );

  test('transient connection failure is not cached', () async {
    var calls = 0;
    final service = SafeImageFileService(
      MockClient((_) async {
        if (++calls == 1) throw const SocketException('fixture outage');
        return http.Response.bytes(png, 200);
      }),
      files: ImageTransferFiles(directory: root),
      lookup: (_) async => [InternetAddress('8.8.8.8')],
    );
    await expectLater(
      service.get('https://lain.bgm.tv/fixture'),
      throwsA(isA<SocketException>()),
    );
    await (await service.get(
      'https://lain.bgm.tv/fixture',
    )).content.drain<void>();
    expect(calls, 2);
  });

  test('long JPEG APP metadata cannot bypass pixel validation', () async {
    final bytes =
        BytesBuilder()
          ..add([255, 216, 255, 225, 255, 255])
          ..add(List.filled(65533, 0))
          ..add([255, 192, 0, 17, 8, 39, 16, 39, 16])
          ..add(List.filled(12, 0));
    final service = SafeImageFileService(
      MockClient((_) async => http.Response.bytes(bytes.toBytes(), 200)),
      files: ImageTransferFiles(directory: root),
      lookup: (_) async => [InternetAddress('8.8.8.8')],
    );
    await expectLater(
      service.get('https://lain.bgm.tv/large.jpg'),
      throwsA(
        isA<HttpException>().having(
          (e) => e.message,
          'limit',
          'Image pixel limit exceeded',
        ),
      ),
    );
  });

  test('strict PNG magic and signed BMP dimensions', () {
    final invalid = Uint8List(40)..setRange(0, 4, [137, 80, 78, 71]);
    expect(hasImageMagic(invalid), false);
    expect(parseImageHeader(invalid), isNull);
    final bmp =
        Uint8List(54)
          ..[0] = 66
          ..[1] = 77;
    final data =
        ByteData.sublistView(bmp)
          ..setUint32(14, 40, Endian.little)
          ..setInt32(18, 800, Endian.little)
          ..setInt32(22, -600, Endian.little);
    expect(data.getUint32(14, Endian.little), 40);
    expect(parseImageHeader(bmp)!.pixels, 800 * 600);
  });

  test(
    'truncated JPEG marker padding is rejected without an indexing exception',
    () {
      for (var length = 12; length < 80; length++) {
        final bytes =
            Uint8List(length)
              ..fillRange(0, length, 255)
              ..[1] = 216;
        expect(parseImageHeader(bytes), isNull);
      }
    },
  );

  test(
    'diagnostic ring and file are bounded and contain only predefined fields',
    () async {
      final diagnostics = ImageDiagnostics(enabled: true);
      final file = File('${root.path}/diagnostics.jsonl');
      await diagnostics.open(file);
      for (var i = 0; i < 3000; i++) {
        diagnostics.record(ImageEvent.failed, i, category: 2);
      }
      await diagnostics.flush();
      expect((diagnostics.snapshot['events'] as List).length, 128);
      expect(await file.length(), lessThan(180 * 1024));
      for (final line in await file.readAsLines()) {
        final entry = jsonDecode(line) as Map;
        expect(
          entry.keys.toSet().difference({
            'seq',
            'request',
            'event',
            'category',
            'version',
            'counts',
            'events',
          }),
          isEmpty,
        );
      }
    },
  );

  test('opening diagnostics preserves the preceding session', () async {
    final file = await File(
      '${root.path}/images.jsonl',
    ).writeAsString('old session');
    await ImageDiagnostics(enabled: true).open(file);
    expect(await File('${file.path}.previous').readAsString(), 'old session');
    expect(await file.readAsString(), contains('version'));
  });
}
