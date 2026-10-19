import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../network/platform_http_client.dart';

@immutable
class ComposeNetworkSample {
  const ComposeNetworkSample({
    required this.name,
    this.headersMs,
    this.totalMs,
    this.error,
    this.status,
  });
  final String name;
  final int? headersMs, totalMs, status;
  final String? error;
}

class NetworkDiagnosticsService {
  NetworkDiagnosticsService({http.Client? client})
    : _client = client ?? createPlatformHttpClient();
  final http.Client _client;
  bool _closed = false;
  static final endpoints = {
    'Bangumi API': Uri.parse('https://next.bgm.tv/p1/calendar'),
    'Bangumi Web': Uri.parse('https://bgm.tv/'),
    'Image CDN': Uri.parse('https://lain.bgm.tv/img/favicon.ico'),
    'GitHub': Uri.parse(
      'https://api.github.com/repos/Androdevell/bangumi-flutter/releases/latest',
    ),
  };
  Future<ComposeNetworkSample> sample(String name, Uri uri) async {
    final watch = Stopwatch()..start();
    int? headerMs;
    try {
      if (_closed) throw StateError('closed');
      final response = await _client
          .send(
            http.Request('GET', uri)
              ..headers['cache-control'] = 'no-cache'
              ..headers['accept'] = '*/*',
          )
          .timeout(const Duration(seconds: 12));
      headerMs = watch.elapsedMilliseconds;
      await response.stream.drain<void>().timeout(const Duration(seconds: 12));
      return ComposeNetworkSample(
        name: name,
        headersMs: Platform.isAndroid ? null : headerMs,
        totalMs: watch.elapsedMilliseconds,
        status: response.statusCode,
        error:
            response.statusCode >= 400 ? 'HTTP ${response.statusCode}' : null,
      );
    } on TimeoutException {
      return ComposeNetworkSample(name: name, error: 'networkTimeout');
    } on Object {
      return ComposeNetworkSample(name: name, error: 'networkFailed');
    }
  }

  void close() {
    _closed = true;
    _client.close();
  }
}
