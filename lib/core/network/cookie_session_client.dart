import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../auth/secure_vault.dart';
import '../app_identity.dart';

class PersistentCookieStore {
  PersistentCookieStore(this._vault);

  static const _storageKey = 'bangumi.cookies.v1';
  static final _cookieSeparator = RegExp(
    r",(?=\s*[!#$%&'*+\-.^_`|~0-9A-Za-z]+=)",
  );

  final SecureVault _vault;
  final List<_StoredCookie> _cookies = [];
  int _generation = 0;
  Future<void> _storageOperations = Future.value();

  int get generation => _generation;

  Future<void> initialize() async {
    final encoded = await _vault.read(_storageKey);
    if (encoded == null || encoded.isEmpty) return;
    final List<dynamic> values;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return;
      values = decoded;
    } on FormatException {
      // Cookie 库无法解析时仍允许恢复 OAuth，保留原始数据，不阻断整个应用启动。
      return;
    }
    _cookies.clear();
    for (final item in values.whereType<Map>()) {
      try {
        final cookie = _StoredCookie.fromJson(Map<String, dynamic>.from(item));
        if (!cookie.isExpired) _cookies.add(cookie);
      } on Object {
        // 单条旧记录损坏不能删除整个 Cookie 库；原始密文仍保留，允许重试恢复。
      }
    }
  }

  String? authenticationUserAgent(Uri uri) {
    for (final cookie in _cookies) {
      if (cookie.name == 'chii_auth' &&
          !cookie.isExpired &&
          cookie.matches(uri)) {
        return cookie.userAgent ?? browserUserAgent;
      }
    }
    return null;
  }

  String? headerFor(Uri uri) {
    _cookies.removeWhere((cookie) => cookie.isExpired);
    final matching =
        _cookies.where((cookie) => cookie.matches(uri)).toList()..sort(
          (left, right) => right.path.length.compareTo(left.path.length),
        );
    if (matching.isEmpty) return null;
    return matching
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }

  Future<void> capture(
    Uri uri,
    String? setCookieHeader, {
    int? requestGeneration,
    String? userAgent,
  }) async {
    if (requestGeneration != null && requestGeneration != _generation) return;
    if (setCookieHeader == null || setCookieHeader.isEmpty) return;
    for (final value in setCookieHeader.split(_cookieSeparator)) {
      _captureOne(uri, value.trim(), userAgent: userAgent);
    }
    _cookies.removeWhere((cookie) => cookie.isExpired);
    await _persist();
  }

  Future<void> clear() async {
    _generation++;
    _cookies.clear();
    await _queueStorage(() => _vault.delete(_storageKey));
  }

  void _captureOne(Uri uri, String value, {String? userAgent}) {
    try {
      final parsed = Cookie.fromSetCookieValue(value);
      final hostOnly = parsed.domain == null || parsed.domain!.isEmpty;
      final domain = (hostOnly ? uri.host : parsed.domain!)
          .toLowerCase()
          .replaceFirst(RegExp(r'^\.'), '');
      if (uri.host != domain && !uri.host.endsWith('.$domain')) return;
      final path =
          parsed.path?.isNotEmpty == true
              ? parsed.path!
              : _defaultPath(uri.path);
      final expiresAt =
          parsed.maxAge == null
              ? parsed.expires
              : DateTime.now().add(Duration(seconds: parsed.maxAge!));
      final cookie = _StoredCookie(
        name: parsed.name,
        value: parsed.value,
        domain: domain,
        path: path,
        secure: parsed.secure,
        hostOnly: hostOnly,
        expiresAt: expiresAt,
        userAgent:
            parsed.name == 'chii_auth' ? userAgent ?? browserUserAgent : null,
      );
      _cookies.removeWhere(
        (item) =>
            item.name == cookie.name &&
            item.domain == cookie.domain &&
            item.path == cookie.path,
      );
      if (parsed.maxAge != 0 && !cookie.isExpired) _cookies.add(cookie);
    } on Object {
      // Ignore a malformed cookie without discarding the rest of the response.
    }
  }

  String _defaultPath(String requestPath) {
    if (!requestPath.startsWith('/') || requestPath == '/') return '/';
    final slash = requestPath.lastIndexOf('/');
    return slash <= 0 ? '/' : requestPath.substring(0, slash);
  }

  Future<void> _persist() {
    final generation = _generation;
    final encoded = jsonEncode(
      _cookies.map((cookie) => cookie.toJson()).toList(),
    );
    return _queueStorage(() async {
      if (generation == _generation) await _vault.write(_storageKey, encoded);
    });
  }

  Future<void> _queueStorage(Future<void> Function() operation) {
    final pending = _storageOperations.then((_) => operation());
    _storageOperations = pending.catchError((Object _) {});
    return pending;
  }
}

class CookieSessionClient extends http.BaseClient {
  CookieSessionClient(this._inner, this._cookies);

  final http.Client _inner;
  final PersistentCookieStore _cookies;
  http.Client get anonymousTransport => _inner;

  bool hasWebAuthentication(Uri uri) =>
      (_cookies.headerFor(uri)?.split('; ') ?? const <String>[]).any(
        (value) => value.startsWith('chii_auth=') && value.length > 10,
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final generation = _cookies.generation;
    // 网页认证沿用签发该 Cookie 时的浏览器标识，不被安装版本或平台默认 UA 改写。
    final agent = _cookies.authenticationUserAgent(request.url);
    if (agent != null) request.headers[HttpHeaders.userAgentHeader] = agent;
    final stored = _cookies.headerFor(request.url);
    final existing = request.headers[HttpHeaders.cookieHeader];
    if (stored != null) {
      request.headers[HttpHeaders.cookieHeader] =
          existing == null ? stored : '$existing; $stored';
    }

    final response = await _inner.send(request);
    await _cookies.capture(
      request.url,
      response.headers[HttpHeaders.setCookieHeader],
      requestGeneration: generation,
      userAgent: request.headers[HttpHeaders.userAgentHeader],
    );
    return response;
  }

  @override
  void close() => _inner.close();
}

class _StoredCookie {
  const _StoredCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.secure,
    required this.hostOnly,
    required this.expiresAt,
    this.userAgent,
  });

  factory _StoredCookie.fromJson(Map<String, dynamic> json) => _StoredCookie(
    name: json['name'] as String? ?? '',
    value: json['value'] as String? ?? '',
    domain: json['domain'] as String? ?? '',
    path: json['path'] as String? ?? '/',
    secure: json['secure'] as bool? ?? false,
    hostOnly: json['hostOnly'] as bool? ?? true,
    expiresAt:
        json['expiresAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
              int.parse(json['expiresAt'].toString()),
            ),
    userAgent: json['userAgent'] as String?,
  );

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final bool hostOnly;
  final DateTime? expiresAt;
  final String? userAgent;

  bool get isExpired => expiresAt?.isBefore(DateTime.now()) ?? false;

  bool matches(Uri uri) {
    final host = uri.host.toLowerCase();
    final domainMatches =
        hostOnly ? host == domain : host == domain || host.endsWith('.$domain');
    final requestPath = uri.path.isEmpty ? '/' : uri.path;
    final pathMatches =
        requestPath == path ||
        (requestPath.startsWith(path) &&
            (path.endsWith('/') ||
                requestPath.substring(path.length).startsWith('/')));
    return domainMatches && pathMatches && (!secure || uri.scheme == 'https');
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'secure': secure,
    'hostOnly': hostOnly,
    'expiresAt': expiresAt?.millisecondsSinceEpoch,
    if (userAgent != null) 'userAgent': userAgent,
  };
}
