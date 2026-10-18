import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:win_http/win_http.dart';

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/131.0.0.0 Safari/537.36 BangumiFlutter/1.2.3';

http.Client createPlatformHttpClient() {
  if (Platform.isAndroid) {
    return AndroidBangumiHttpClient();
  }

  if (Platform.isWindows) {
    return WinHttpClient.fromConfiguration(
      const WinHttpClientConfiguration(
        userAgent: _userAgent,
        accessType: WinHttpAccessType.automatic,
        resolveTimeout: Duration(seconds: 15),
        connectTimeout: Duration(seconds: 15),
        sendTimeout: Duration(seconds: 20),
        receiveTimeout: Duration(seconds: 20),
        maxConnectionsPerServer: 20,
      ),
    );
  }

  return IOClient(HttpClient()..userAgent = _userAgent);
}

class AndroidBangumiHttpClient extends http.BaseClient {
  static const _channel = MethodChannel('com.xiaoyv.bangumi/network');

  bool _closed = false;
  static int _nextRequest = 0;
  final Set<String> _requests = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw http.ClientException('HTTP client is closed', request.url);
    }

    final body = await request.finalize().toBytes();
    final requestId = 'dart-${++_nextRequest}';
    _requests.add(requestId);
    var aborted = false;
    if (request is http.Abortable) {
      unawaited(
        request.abortTrigger?.then((_) async {
          if (!_requests.contains(requestId)) return;
          aborted = true;
          try {
            await _channel.invokeMethod<void>('cancelRequest', {
              'requestId': requestId,
            });
          } on PlatformException {
            /* 原请求仍会由超时/关闭释放。 */
          }
        }),
      );
    }
    try {
      final rawResponse = await _channel.invokeMapMethod<String, dynamic>(
        'request',
        <String, dynamic>{
          'method': request.method,
          'requestId': requestId,
          'url': request.url.toString(),
          'followRedirects': request.followRedirects,
          'headers': <String, String>{
            ...request.headers,
            if (!request.headers.containsKey(HttpHeaders.userAgentHeader))
              HttpHeaders.userAgentHeader: _userAgent,
          },
          'body': body,
        },
      );
      if (aborted) throw http.RequestAbortedException(request.url);
      if (rawResponse == null) {
        throw http.ClientException(
          'Android network returned no response',
          request.url,
        );
      }

      final statusCode = rawResponse['statusCode'] as int;
      final responseHeaders = (rawResponse['headers'] as Map<Object?, Object?>)
          .map(
            (key, value) =>
                MapEntry(key.toString().toLowerCase(), value.toString()),
          );
      final responseBody = rawResponse['body'];
      final bytes =
          responseBody is Uint8List
              ? responseBody
              : Uint8List.fromList((responseBody as List<Object?>).cast<int>());

      return http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        statusCode,
        contentLength: bytes.length,
        headers: responseHeaders,
        reasonPhrase: rawResponse['reasonPhrase'] as String?,
        isRedirect: rawResponse['isRedirect'] as bool? ?? false,
        request: request,
      );
    } on PlatformException catch (error) {
      if (aborted) throw http.RequestAbortedException(request.url);
      throw http.ClientException(
        error.message ?? 'Android network request failed',
        request.url,
      );
    } finally {
      _requests.remove(requestId);
    }
  }

  @override
  void close() {
    _closed = true;
    for (final id in _requests) {
      unawaited(
        _channel
            .invokeMethod<void>('cancelRequest', {'requestId': id})
            .catchError((Object _) {}),
      );
    }
  }
}
