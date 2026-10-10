import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../auth/auth_service.dart';
import 'platform_http_client.dart';

class ApiClient {
  ApiClient({
    http.Client? client,
    Uri? baseUri,
    AuthService? authService,
    Duration cacheTtl = const Duration(minutes: 5),
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
  }) : _client = client ?? createPlatformHttpClient(),
       _cacheTtl = cacheTtl,
       _delay = delay ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now,
       _authService = authService,
       _baseUri =
           baseUri ??
           Uri.parse(
             const String.fromEnvironment(
               'BGM_API_BASE_URL',
               defaultValue: 'https://next.bgm.tv/',
             ),
           ) {
    _authService?.addListener(clearCache);
  }

  final http.Client _client;
  final AuthService? _authService;
  final Uri _baseUri;
  final Duration _cacheTtl;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _clock;
  final Map<String, ({DateTime at, dynamic value})> _cache = {};
  final Map<String, Future<dynamic>> _inFlight = {};
  int _cacheGeneration = 0;
  final Queue<Completer<void>> _waiters = Queue();
  int _activeRequests = 0;

  void clearCache() {
    _cacheGeneration++;
    _cache.clear();
    _inFlight.clear();
  }

  Future<dynamic> _cachedGet(String path, Map<String, String>? query) async {
    final keys = query?.keys.toList() ?? <String>[];
    keys.sort();
    final key =
        '$currentUsername:$path:${jsonEncode({for (final k in keys) k: query![k]})}';
    final cached = _cache[key];
    if (cached != null && _clock().difference(cached.at) < _cacheTtl) {
      return cached.value;
    }
    if (_inFlight[key] case final running?) return running;
    final generation = _cacheGeneration;
    final request = _request('GET', path, query: query);
    _inFlight[key] = request;
    try {
      final result = await request;
      if (generation == _cacheGeneration) {
        if (_cache.length >= 200) _cache.remove(_cache.keys.first);
        _cache[key] = (at: _clock(), value: result);
      }
      return result;
    } finally {
      if (identical(_inFlight[key], request)) _inFlight.remove(key);
    }
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _cachedGet(path, query);

  Future<dynamic> post(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) => _request('POST', path, query: query, body: body);

  Future<dynamic> put(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) => _request('PUT', path, query: query, body: body, requiresAuth: true);

  Future<dynamic> patch(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) => _request('PATCH', path, query: query, body: body, requiresAuth: true);

  Future<dynamic> delete(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) => _request('DELETE', path, query: query, body: body, requiresAuth: true);

  bool get isLoggedIn => _authService?.isLoggedIn ?? false;
  String get currentUsername => _authService?.user?.username ?? '';

  Future<dynamic> postWebForm(
    String path, {
    required Map<String, String> fields,
    String? referer,
  }) async {
    final uri = Uri.parse('https://bgm.tv/').resolve(path);
    final request =
        http.Request('POST', uri)
          ..followRedirects = false
          ..headers.addAll({
            HttpHeaders.acceptHeader: 'application/json,*/*;q=0.8',
            HttpHeaders.acceptLanguageHeader:
                'zh-CN,zh;q=0.8,zh-TW;q=0.6,zh-HK;q=0.4,en;q=0.2',
            HttpHeaders.refererHeader: referer ?? 'https://bgm.tv/',
            HttpHeaders.cookieHeader: 'kira=4',
          })
          ..bodyFields = fields;
    try {
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 20)),
      );
      final text = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          response.statusCode >= 300 && response.statusCode < 400
              ? '评论未发布，登录会话可能已过期，请重新登录后再试'
              : '服务器返回 ${response.statusCode}',
          statusCode: response.statusCode,
          details: text,
        );
      }
      if (text.isEmpty) {
        throw const ApiException('未收到评论发布确认，请刷新确认后再试');
      }
      clearCache();
      try {
        return jsonDecode(text);
      } on FormatException {
        throw const ApiException('评论发布失败，请重新登录后再试');
      }
    } on TimeoutException {
      throw const ApiException('连接 Bangumi 超时，请检查网络后重试');
    } on SocketException {
      throw const ApiException('无法连接 Bangumi，请检查网络或 DNS 设置');
    } on http.ClientException catch (error) {
      throw ApiException('网络请求失败：${error.message}');
    }
  }

  String get formHash => _authService?.user?.formHash ?? '';

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool requiresAuth = false,
  }) async {
    final uri = _baseUri.resolve(path).replace(queryParameters: query);

    try {
      var accessToken = await _authService?.validAccessToken();
      if (requiresAuth && _authService != null && accessToken == null) {
        throw const ApiException('登录已失效，请重新登录后再操作');
      }
      var response = await _send(method, uri, body, accessToken);
      if (response.statusCode == HttpStatus.unauthorized &&
          accessToken != null &&
          await (_authService?.refreshAccessToken() ?? Future.value(false))) {
        accessToken = await _authService?.validAccessToken();
        if (requiresAuth && accessToken == null) {
          throw const ApiException('登录已失效，请重新登录后再操作');
        }
        response = await _send(method, uri, body, accessToken);
      }
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          response.statusCode == 401
              ? '登录已失效，请重新登录'
              : response.statusCode == 429
              ? '请求过于频繁，请稍后重试'
              : '服务器返回 ${response.statusCode}',
          statusCode: response.statusCode,
          details: text,
        );
      }
      if (method != 'GET' && method != 'POST') clearCache();
      if (text.trim().isEmpty) return null;
      try {
        return jsonDecode(text);
      } on FormatException {
        throw const ApiException('服务器返回了无法识别的数据');
      }
    } on TimeoutException {
      throw const ApiException('连接 Bangumi 超时，请检查网络后重试');
    } on SocketException {
      throw const ApiException('无法连接 Bangumi，请检查网络或 DNS 设置');
    } on http.ClientException catch (error) {
      throw ApiException('网络请求失败：${error.message}');
    }
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    Object? body,
    String? accessToken,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await _sendLimited(method, uri, body, accessToken);
        if (method != 'GET' ||
            attempt >= 2 ||
            !{429, 502, 503, 504}.contains(response.statusCode)) {
          return response;
        }
        final wait = _retryDelay(response, attempt);
        // 长时间限流交给 UI 提示，不提前重试违反服务端的 Retry-After。
        if (wait > const Duration(seconds: 10)) return response;
        await _delay(wait);
      } on Object catch (error) {
        if (method != 'GET' ||
            attempt >= 2 ||
            !(error is SocketException ||
                error is TimeoutException ||
                error is http.ClientException)) {
          rethrow;
        }
        await _delay(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
  }

  Duration _retryDelay(http.Response response, int attempt) {
    final header = response.headers['retry-after'];
    if (header != null) {
      final seconds = int.tryParse(header);
      if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
      try {
        final wait = HttpDate.parse(header).difference(_clock());
        return wait.isNegative ? Duration.zero : wait;
      } on FormatException {
        /* 使用短退避 */
      }
    }
    return Duration(milliseconds: 500 * (1 << attempt));
  }

  Future<http.Response> _sendLimited(
    String method,
    Uri uri,
    Object? body,
    String? accessToken,
  ) async {
    if (_activeRequests >= 3) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    } else {
      _activeRequests++;
    }
    try {
      return await _sendOnce(method, uri, body, accessToken);
    } finally {
      if (_waiters.isEmpty) {
        _activeRequests--;
      } else {
        _waiters.removeFirst().complete();
      }
    }
  }

  Future<http.Response> _sendOnce(
    String method,
    Uri uri,
    Object? body,
    String? accessToken,
  ) async {
    final request = http.Request(method, uri)
      ..headers.addAll({
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        HttpHeaders.acceptLanguageHeader:
            'zh-CN,zh;q=0.8,zh-TW;q=0.6,zh-HK;q=0.4,en;q=0.2',
        HttpHeaders.cookieHeader: 'kira=4',
        if (accessToken != null)
          HttpHeaders.authorizationHeader: 'Bearer $accessToken',
      });
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    return http.Response.fromStream(
      streamed,
    ).timeout(const Duration(seconds: 20));
  }

  void close() {
    _authService?.removeListener(clearCache);
    clearCache();
    _client.close();
  }
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.details});

  final String message;
  final int? statusCode;
  final String? details;

  @override
  String toString() {
    final body = details?.trim() ?? '';
    if (body.isEmpty) return message;
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final detail = json['message'] ?? json['error'] ?? json['detail'];
        if (detail != null && '$detail'.trim().isNotEmpty) {
          return '$message：$detail';
        }
      }
    } on FormatException {
      // Ignore non-JSON error pages.
    }
    return message;
  }
}
