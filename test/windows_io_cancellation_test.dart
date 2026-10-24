import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:bangumi_flutter/core/network/windows_system_client.dart';

void main() {
  test(
    'Dart Windows transport cancels in-flight reads and stays responsive',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        try {
          request.response.headers.contentType = ContentType.binary;
          for (var i = 0; i < 15; i++) {
            request.response.add(List.filled(2048, i));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 8));
          }
          await request.response.close();
        } on Object {
          /* 客户端取消连接是本测试预期。 */
        }
      });
      final client = WindowsSystemClient(resolve: (_) async => 'DIRECT');
      addTearDown(client.close);
      var beats = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 2),
        (_) => beats++,
      );
      addTearDown(timer.cancel);
      for (var i = 0; i < 12; i++) {
        final abort = Completer<void>();
        final response = await client.send(
          http.AbortableRequest(
            'GET',
            Uri.parse('http://127.0.0.1:${server.port}/test'),
            abortTrigger: abort.future,
          ),
        );
        final done = Completer<void>();
        late StreamSubscription<List<int>> sub;
        sub = response.stream.listen(
          (_) {
            if (!abort.isCompleted) abort.complete();
          },
          onError: (Object _) {
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );
        await done.future.timeout(const Duration(seconds: 3));
        await sub.cancel();
      }
      expect(beats, greaterThan(10));
      client.close();
      await expectLater(
        client.get(Uri.parse('http://127.0.0.1:${server.port}')),
        throwsA(isA<http.ClientException>()),
      );
    },
  );
}
