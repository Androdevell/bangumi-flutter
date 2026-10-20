import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ResponseLimitException implements Exception {
  const ResponseLimitException();
  @override
  String toString() => 'responseTooLarge';
}

/// 同时限制声明大小、实际字节及总读取时间，失败即取消消费。
Future<http.Response> readBoundedResponse(
  http.StreamedResponse response, {
  int maxBytes = 4 * 1024 * 1024,
  Duration timeout = const Duration(seconds: 20),
}) async {
  if ((response.contentLength ?? 0) > maxBytes) {
    await response.stream.listen((_) {}).cancel();
    throw const ResponseLimitException();
  }
  final result = Completer<http.Response>();
  final bytes = BytesBuilder(copy: false);
  StreamSubscription<List<int>>? subscription;
  void fail(Object error, [StackTrace? stack]) {
    if (result.isCompleted) return;
    result.completeError(error, stack);
    unawaited(subscription?.cancel());
  }

  final timer = Timer(
    timeout,
    () => fail(TimeoutException('Response budget exceeded')),
  );
  subscription = response.stream.listen(
    (chunk) {
      if (result.isCompleted) return;
      if (bytes.length + chunk.length > maxBytes) {
        fail(const ResponseLimitException());
      } else {
        bytes.add(chunk);
      }
    },
    onError: fail,
    onDone: () {
      if (!result.isCompleted) {
        result.complete(
          http.Response.bytes(
            bytes.takeBytes(),
            response.statusCode,
            headers: response.headers,
            request: response.request,
            reasonPhrase: response.reasonPhrase,
            isRedirect: response.isRedirect,
            persistentConnection: response.persistentConnection,
          ),
        );
      }
    },
  );
  try {
    return await result.future;
  } finally {
    timer.cancel();
  }
}

Object? _parseJson(Uint8List bytes) =>
    jsonDecode(utf8.decode(bytes, allowMalformed: true));

Future<dynamic> decodeResponseJson(http.Response response) async =>
    response.bodyBytes.length < 64 * 1024
        ? _parseJson(response.bodyBytes)
        : compute(_parseJson, response.bodyBytes);
