import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../../app/state/session_scope.dart';
import '../cache/query_key.dart';
import 'platform_http_client.dart';
import 'cookie_session_client.dart';
import '../diagnostics/network_timing.dart';

class ApiClient {
  ApiClient({
    http.Client? client,
    Uri? baseUri,
    AuthService? authService,
    Duration cacheTtl = const Duration(minutes: 5),
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
    bool closeClient = true,
    Duration readBudget = const Duration(seconds: 12),
  }) : _client = client ?? createPlatformHttpClient(),
       _closeClient = closeClient,
       _cacheTtl = cacheTtl,
       _delay = delay ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now,
       _readBudget = readBudget,
       _authService = authService,
       _baseUri =
           baseUri ??
           Uri.parse(
             const String.fromEnvironment(
               'BGM_API_BASE_URL',
               defaultValue: 'https://next.bgm.tv/',
             ),
           ) {
    _sessionChanges = ValueNotifier(sessionScope);
    _authService?.addListener(_onAuthChanged);
  }

  final http.Client _client;
  final bool _closeClient;
  final AuthService? _authService;
  final Uri _baseUri;
  final Duration _cacheTtl;
  final Duration _readBudget;
  final Set<Completer<void>> _activeAborts = {};
  Future<dynamic>? _publicCalendar;
  DateTime? _publicCalendarAt;
  int _publicCalendarGeneration = 0;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _clock;
  final Map<QueryKey, ({DateTime at, dynamic value})> _cache = {};
  final Map<QueryKey, Future<dynamic>> _inFlight = {};
  late final ValueNotifier<SessionScope> _sessionChanges;
  int _permissionRevision = 0;
  bool _closed = false;
  int _cacheGeneration = 0;
  final Queue<Completer<void>> _waiters = Queue();
  int _activeRequests = 0;

  SessionScope get sessionScope => SessionScope(
    username: currentUsername,
    accountId: _authService?.user?.id ?? 0,
    epoch: _authService?.sessionEpoch ?? 0,
  );
  Listenable get sessionChanges => _sessionChanges;

  void _onAuthChanged() {
    if (_sessionChanges.value == sessionScope) return;
    _permissionRevision++;
    clearCache();
    _sessionChanges.value = sessionScope;
  }

  void _requireScope(SessionScope scope) {
    if (_closed || scope != sessionScope) {
      throw const ApiException('登录会话已改变，请重新加载后操作');
    }
  }

  void invalidateResources(Set<String> paths) {
    if (paths.contains('p1/calendar')) _invalidatePublicCalendar();
    _cacheGeneration++;
    bool matches(QueryKey key) =>
        paths.any((path) => key.path.startsWith(path));
    _cache.removeWhere((key, _) => matches(key));
    _inFlight.removeWhere((key, _) => matches(key));
  }

  void clearCache() {
    _cacheGeneration++;
    _cache.clear();
    _inFlight.clear();
    _invalidatePublicCalendar();
  }

  void _invalidatePublicCalendar() {
    _publicCalendarGeneration++;
    _publicCalendar = null;
    _publicCalendarAt = null;
  }

  /// 只允许已验证的公开日历读取，绕过登录 Cookie 和令牌刷新。
  Future<dynamic> publicCalendar() {
    if (_closed) return Future.error(const ApiException('客户端已关闭'));
    if (_publicCalendarAt != null &&
        _clock().difference(_publicCalendarAt!) >= _cacheTtl) {
      _invalidatePublicCalendar();
    }
    return _publicCalendar ??= _loadPublicCalendar(_publicCalendarGeneration);
  }

  Future<dynamic> _loadPublicCalendar(int generation) async {
    final budget = _ReadBudget(_readBudget);
    final transport =
        _client is CookieSessionClient ? (_client).anonymousTransport : _client;
    try {
      final response = await _sendOnce(
        'GET',
        _baseUri.resolve('p1/calendar'),
        null,
        null,
        budget,
        transport: transport,
        anonymous: true,
      );
      if (response.statusCode != 200) {
        throw ApiException(
          '服务器返回 ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      if (_closed) throw const ApiException('客户端已关闭');
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (generation == _publicCalendarGeneration) _publicCalendarAt = _clock();
      return data;
    } on Object {
      if (generation == _publicCalendarGeneration) _invalidatePublicCalendar();
      rethrow;
    }
  }

  Future<dynamic> _cachedGet(
    String path,
    Map<String, String>? query, {
    bool fresh = false,
  }) async {
    if (fresh) invalidateResources({path});
    final key = QueryKey(
      environment: _baseUri.toString(),
      session: sessionScope,
      permissionRevision: _permissionRevision,
      path: path,
      query: query,
    );
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

  Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    bool fresh = false,
  }) => _cachedGet(path, query, fresh: fresh);

  Future<dynamic> post(
    String path, {
    Map<String, String>? query,
    Object? body,
    bool readOnly = false,
  }) => _request('POST', path, query: query, body: body, mutation: !readOnly);

  Future<dynamic> put(
    String path, {
    Map<String, String>? query,
    Object? body,
    SessionScope? expectedScope,
    Set<String>? invalidatePaths,
  }) => _request(
    'PUT',
    path,
    query: query,
    body: body,
    requiresAuth: true,
    expectedScope: expectedScope,
    invalidatePaths: invalidatePaths,
  );

  Future<dynamic> patch(
    String path, {
    Map<String, String>? query,
    Object? body,
    SessionScope? expectedScope,
    Set<String>? invalidatePaths,
  }) => _request(
    'PATCH',
    path,
    query: query,
    body: body,
    requiresAuth: true,
    expectedScope: expectedScope,
    invalidatePaths: invalidatePaths,
  );

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
    final scope = sessionScope;
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
      _requireScope(scope);
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 20)),
      ).timeout(const Duration(seconds: 20));
      _requireScope(scope);
      final text = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          response.statusCode >= 300 && response.statusCode < 400
              ? '评论未发布，登录会话可能已过期，请重新登录后再试'
              : '服务器返回 ${response.statusCode}',
          statusCode: response.statusCode,
          details: text,
          outcomeUnknown:
              response.statusCode >= 500 ||
              response.statusCode == 408 ||
              (response.statusCode >= 300 &&
                  response.statusCode < 400 &&
                  !(Uri.tryParse(
                        response.headers['location'] ?? '',
                      )?.path.contains('login') ??
                      false)),
        );
      }
      if (text.isEmpty) {
        throw const ApiException('未收到评论发布确认，请刷新确认后再试', outcomeUnknown: true);
      }
      try {
        return jsonDecode(text);
      } on FormatException {
        throw const ApiException('评论发布失败，请重新登录后再试', outcomeUnknown: true);
      }
    } on TimeoutException {
      throw const ApiException('连接 Bangumi 超时，请检查网络后重试', outcomeUnknown: true);
    } on SocketException {
      throw const ApiException(
        '无法连接 Bangumi，请检查网络或 DNS 设置',
        outcomeUnknown: true,
      );
    } on http.ClientException catch (error) {
      throw ApiException('网络请求失败：${error.message}', outcomeUnknown: true);
    }
  }

  String get formHash => _authService?.user?.formHash ?? '';

  Future<void> updateProfileIdentity({
    required SessionScope scope,
    required String nickname,
    required String avatarUrl,
  }) async {
    _requireScope(scope);
    await _authService?.updateProfileIdentity(
      username: scope.username,
      nickname: nickname,
      avatarUrl: avatarUrl,
    );
    _requireScope(scope);
  }

  /// 账号资料通道固定为本站 settings，不接收外部提交地址或自动重发写请求。
  Future<String> accountSettings({
    required SessionScope scope,
    Map<String, String>? fields,
    Uint8List? avatar,
  }) async {
    _requireScope(scope);
    if (!isLoggedIn) throw const ApiException('loginRequired');
    final uri = Uri.parse('https://bgm.tv/settings');
    final http.BaseRequest request;
    if (fields != null) {
      final multipart = http.MultipartRequest('POST', uri)
        ..fields.addAll(fields);
      if (avatar != null) {
        multipart.files.add(
          http.MultipartFile.fromBytes(
            'picfile',
            avatar,
            filename: 'avatar.png',
            contentType: MediaType('image', 'png'),
          ),
        );
      }
      request = multipart;
    } else {
      request = http.Request('GET', uri);
    }
    request.followRedirects = false;
    request.headers.addAll({
      'accept': 'text/html',
      'referer': 'https://bgm.tv/settings',
      'cookie': 'kira=4',
    });
    try {
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 20)),
      ).timeout(const Duration(seconds: 20));
      _requireScope(scope);
      final location = response.headers['location'];
      final redirect = location == null ? null : uri.resolve(location);
      final sameSite =
          redirect != null &&
          redirect.scheme == 'https' &&
          redirect.host == uri.host &&
          redirect.port == 443 &&
          redirect.userInfo.isEmpty;
      if (fields != null &&
          (response.statusCode == 302 || response.statusCode == 303) &&
          sameSite &&
          redirect.path == '/settings') {
        return '';
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final loginRequired =
            response.statusCode == 401 ||
            (response.statusCode >= 300 &&
                response.statusCode < 400 &&
                sameSite &&
                redirect.path == '/login');
        throw ApiException(
          loginRequired
              ? 'profileWebLoginRequired'
              : response.statusCode == 403
              ? 'profileWebUnavailable'
              : response.statusCode == 429
              ? 'profileRateLimited'
              : fields == null
              ? 'profileLoadFailed'
              : 'profileUnconfirmed',
          statusCode: response.statusCode,
          outcomeUnknown:
              fields != null &&
              !loginRequired &&
              (response.statusCode >= 500 ||
                  (response.statusCode >= 300 && response.statusCode < 400)),
        );
      }
      return utf8.decode(response.bodyBytes, allowMalformed: false);
    } on ApiException {
      rethrow;
    } on Object {
      throw ApiException(
        fields == null ? 'profileLoadFailed' : 'profileUnconfirmed',
        outcomeUnknown: fields != null,
      );
    }
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool requiresAuth = false,
    bool? mutation,
    SessionScope? expectedScope,
    Set<String>? invalidatePaths,
  }) async {
    final scope = expectedScope ?? sessionScope;
    final uri = _baseUri.resolve(path).replace(queryParameters: query);
    final budget = method == 'GET' ? _ReadBudget(_readBudget) : null;

    try {
      final authFuture =
          _authService?.validAccessToken() ?? Future<String?>.value();
      final authWatch = Stopwatch()..start();
      var accessToken = await (budget?.wait(authFuture) ?? authFuture);
      NetworkTiming.record('auth', authWatch);
      _requireScope(scope);
      if (requiresAuth && _authService != null && accessToken == null) {
        throw const ApiException('登录已失效，请重新登录后再操作');
      }
      var response = await _send(method, uri, body, accessToken, scope, budget);
      _requireScope(scope);
      if (response.statusCode == HttpStatus.unauthorized &&
          accessToken != null &&
          await (budget?.wait(
                _authService?.refreshAccessToken() ?? Future.value(false),
              ) ??
              (_authService?.refreshAccessToken() ?? Future.value(false)))) {
        accessToken = await _authService?.validAccessToken();
        _requireScope(scope);
        if (requiresAuth && accessToken == null) {
          throw const ApiException('登录已失效，请重新登录后再操作');
        }
        response = await _send(method, uri, body, accessToken, scope, budget);
        _requireScope(scope);
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
      if (mutation ?? method != 'GET') {
        if (invalidatePaths == null) {
          clearCache();
        } else {
          invalidateResources(invalidatePaths);
        }
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
    SessionScope scope,
    _ReadBudget? budget,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await _sendLimited(
          method,
          uri,
          body,
          accessToken,
          scope,
          budget,
        );
        if (method != 'GET' ||
            attempt >= 2 ||
            !{429, 502, 503, 504}.contains(response.statusCode)) {
          return response;
        }
        final wait = _retryDelay(response, attempt);
        // 长时间限流交给 UI 提示，不提前重试违反服务端的 Retry-After。
        if (wait > const Duration(seconds: 10) ||
            (budget != null && wait >= budget.remaining)) {
          return response;
        }
        await (budget?.wait(_delay(wait)) ?? _delay(wait));
      } on Object catch (error) {
        if (method != 'GET' ||
            attempt >= 2 ||
            !(error is SocketException ||
                error is TimeoutException ||
                error is http.ClientException)) {
          rethrow;
        }
        final delay = _delay(Duration(milliseconds: 500 * (1 << attempt)));
        await (budget?.wait(delay) ?? delay);
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
    SessionScope scope,
    _ReadBudget? budget,
  ) async {
    if (_activeRequests >= 3) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      final watch = Stopwatch()..start();
      try {
        await (budget?.wait(waiter.future) ?? waiter.future);
      } on Object {
        if (!_waiters.remove(waiter)) _releaseSlot();
        rethrow;
      }
      NetworkTiming.record('queue', watch);
    } else {
      _activeRequests++;
    }
    try {
      _requireScope(scope);
      return await _sendOnce(method, uri, body, accessToken, budget);
    } finally {
      _releaseSlot();
    }
  }

  void _releaseSlot() {
    if (_waiters.isEmpty) {
      _activeRequests--;
    } else {
      _waiters.removeFirst().complete();
    }
  }

  Future<http.Response> _sendOnce(
    String method,
    Uri uri,
    Object? body,
    String? accessToken,
    _ReadBudget? budget, {
    http.Client? transport,
    bool anonymous = false,
  }) async {
    final timeout = budget?.remaining ?? const Duration(seconds: 20);
    final abort = Completer<void>();
    _activeAborts.add(abort);
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    final request = http.AbortableRequest(
        method,
        uri,
        abortTrigger: abort.future,
      )
      ..headers.addAll({
        HttpHeaders.acceptHeader: 'application/json',
        if (body != null)
          HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        HttpHeaders.acceptLanguageHeader:
            'zh-CN,zh;q=0.8,zh-TW;q=0.6,zh-HK;q=0.4,en;q=0.2',
        if (!anonymous) HttpHeaders.cookieHeader: 'kira=4',
        if (accessToken != null)
          HttpHeaders.authorizationHeader: 'Bearer $accessToken',
      });
    if (body != null) request.body = jsonEncode(body);
    final watch = Stopwatch()..start();
    try {
      final streamed = await (transport ?? _client)
          .send(request)
          .timeout(timeout);
      NetworkTiming.record('headers', watch);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(budget?.remaining ?? const Duration(seconds: 20));
      NetworkTiming.record('response', watch);
      return response;
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
      _activeAborts.remove(abort);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final abort in _activeAborts) {
      if (!abort.isCompleted) abort.complete();
    }
    _authService?.removeListener(_onAuthChanged);
    clearCache();
    _sessionChanges.dispose();
    if (_closeClient) _client.close();
  }
}

class _ReadBudget {
  _ReadBudget(this.duration);
  final Duration duration;
  final Stopwatch watch = Stopwatch()..start();
  Duration get remaining {
    final value = duration - watch.elapsed;
    if (value <= Duration.zero) {
      throw TimeoutException('Read deadline exceeded');
    }
    return value;
  }

  Future<T> wait<T>(Future<T> future) => future.timeout(remaining);
}

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.details,
    this.outcomeUnknown = false,
  });

  final String message;
  final int? statusCode;
  final String? details;
  final bool outcomeUnknown;

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
