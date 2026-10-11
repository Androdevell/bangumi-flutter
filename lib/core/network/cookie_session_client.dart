import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../auth/secure_vault.dart';

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
    try {
      final values = jsonDecode(encoded) as List<dynamic>;
      _cookies
        ..clear()
        ..addAll(
          values
              .whereType<Map>()
              .map(
                (item) =>
                    _StoredCookie.fromJson(Map<String, dynamic>.from(item)),
              )
              .where((cookie) => !cookie.isExpired),
        );
    } on Object {
      await _vault.delete(_storageKey);
    }
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
  }) async {
    if (requestGeneration != null && requestGeneration != _generation) return;
    if (setCookieHeader == null || setCookieHeader.isEmpty) return;
    for (final value in setCookieHeader.split(_cookieSeparator)) {
      _captureOne(uri, value.trim());
    }
    _cookies.removeWhere((cookie) => cookie.isExpired);
    await _persist();
  }

  Future<void> clear() async {
    _generation++;
    _cookies.clear();
    await _queueStorage(() => _vault.delete(_storageKey));
  }

  void _captureOne(Uri uri, String value) {
    try {
      final parsed = Cookie.fromSetCookieValue(value);
      final hostOnly = parsed.domain == null || parsed.domain!.isEmpty;
      final domain = (hostOnly ? uri.host : parsed.domain!)
          .toLowerCase()
          .replaceFirst(RegExp(r'^\.'), '');
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

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final generation = _cookies.generation;
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
            : DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
  );

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final bool hostOnly;
  final DateTime? expiresAt;

  bool get isExpired => expiresAt?.isBefore(DateTime.now()) ?? false;

  bool matches(Uri uri) {
    final host = uri.host.toLowerCase();
    final domainMatches =
        hostOnly ? host == domain : host == domain || host.endsWith('.$domain');
    final pathMatches = uri.path.isEmpty || uri.path.startsWith(path);
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
  };
}
