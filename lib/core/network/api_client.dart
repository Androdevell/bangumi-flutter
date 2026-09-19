import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../auth/auth_service.dart';
import 'platform_http_client.dart';

class ApiClient {
  ApiClient({http.Client? client, Uri? baseUri, AuthService? authService})
    : _client = client ?? createPlatformHttpClient(),
      _authService = authService,
      _baseUri =
          baseUri ??
          Uri.parse(
            const String.fromEnvironment(
              'BGM_API_BASE_URL',
              defaultValue: 'https://next.bgm.tv/',
            ),
          );

  final http.Client _client;
  final AuthService? _authService;
  final Uri _baseUri;

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _request('GET', path, query: query);

  Future<dynamic> post(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) => _request('POST', path, query: query, body: body);

  Future<dynamic> put(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) => _request('PUT', path, query: query, body: body);

  Future<dynamic> patch(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) => _request('PATCH', path, query: query, body: body);

  Future<dynamic> delete(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) => _request('DELETE', path, query: query, body: body);

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
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw ApiException(
          '服务器返回 ${response.statusCode}',
          statusCode: response.statusCode,
          details: response.body,
        );
      }
      final text = utf8.decode(response.bodyBytes).trim();
      if (text.isEmpty || response.statusCode >= 300) return null;
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
  }) async {
    final uri = _baseUri.resolve(path).replace(queryParameters: query);

    try {
      var accessToken = await _authService?.validAccessToken();
      var response = await _send(method, uri, body, accessToken);
      if (response.statusCode == HttpStatus.unauthorized &&
          accessToken != null &&
          await (_authService?.refreshAccessToken() ?? Future.value(false))) {
        accessToken = await _authService?.validAccessToken();
        response = await _send(method, uri, body, accessToken);
      }
      final text = utf8.decode(response.bodyBytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          '服务器返回 ${response.statusCode}',
          statusCode: response.statusCode,
          details: text,
        );
      }
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
    return http.Response.fromStream(streamed);
  }

  void close() => _client.close();
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
