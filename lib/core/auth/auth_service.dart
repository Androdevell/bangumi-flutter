import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../network/cookie_session_client.dart';
import 'auth_models.dart';
import 'secure_vault.dart';

class AuthService extends ChangeNotifier {
  AuthService({
    required http.Client client,
    required PersistentCookieStore cookies,
    required SecureVault vault,
    String appId = const String.fromEnvironment('BGM_OAUTH_APP_ID'),
    String appSecret = const String.fromEnvironment('BGM_OAUTH_APP_SECRET'),
  }) : _client = client,
       _cookies = cookies,
       _vault = vault,
       _appId = appId,
       _appSecret = appSecret;

  static const _userStorageKey = 'bangumi.auth.user.v1';
  static const _tokenStorageKey = 'bangumi.auth.token.v1';
  static const _callback = 'http://localhost/callback';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36 BangumiFlutter/1.0';

  final http.Client _client;
  final PersistentCookieStore _cookies;
  final SecureVault _vault;
  final String _appId;
  final String _appSecret;

  AuthUser? _user;
  AuthToken? _token;
  Future<bool>? _refreshing;

  AuthUser? get user => _user;
  bool get isLoggedIn => _user != null && _token != null;

  Future<void> initialize() async {
    try {
      final storedUser = await _vault.read(_userStorageKey);
      final storedToken = await _vault.read(_tokenStorageKey);
      if (storedUser != null && storedToken != null) {
        _user = AuthUser.fromJson(
          Map<String, dynamic>.from(jsonDecode(storedUser) as Map),
        );
        _token = AuthToken.fromJson(
          Map<String, dynamic>.from(jsonDecode(storedToken) as Map),
        );
      }
    } on Object {
      await _clearCredentials();
    }
  }

  Future<LoginChallenge> beginLogin() async {
    if (_appId.isEmpty || _appSecret.isEmpty) {
      throw const AuthException('当前构建未配置 Bangumi OAuth，请通过 dart-define 提供应用凭据');
    }
    final response = await _request('GET', _webUri('login'));
    _requireSuccess(response, '加载登录页面失败');
    final document = html.parse(response.body);
    final loginForm = document.querySelector('#loginForm');

    if (loginForm == null) {
      final existingUser = _parseUser(document);
      if (existingUser != null) {
        await _completeLogin(existingUser);
        return const LoginChallenge({});
      }
      throw const AuthException('登录页面格式发生变化，请稍后重试');
    }

    final fields = <String, String>{};
    for (final input in loginForm.querySelectorAll('input')) {
      final name = input.attributes['name']?.trim() ?? '';
      if (name.isNotEmpty) fields[name] = input.attributes['value'] ?? '';
    }
    fields.putIfAbsent('referer', () => 'https://bgm.tv/');
    fields.putIfAbsent('dreferer', () => 'https://bgm.tv/');
    fields.remove('cookietime');
    return LoginChallenge(fields);
  }

  Future<Uint8List> loadCaptcha() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await _request(
      'GET',
      _webUri('signup/captcha').replace(query: '$timestamp'),
      headers: {HttpHeaders.acceptHeader: 'image/avif,image/webp,image/*,*/*'},
    );
    _requireSuccess(response, '获取验证码失败');
    return response.bodyBytes;
  }

  Future<void> login({
    required String email,
    required String password,
    required String captcha,
    required LoginChallenge challenge,
  }) async {
    if (email.trim().isEmpty || password.isEmpty || captcha.trim().isEmpty) {
      throw const AuthException('请填写邮箱、密码和验证码');
    }

    final fields = <String, String>{
      ...challenge.hiddenFields,
      'email': email.trim(),
      'password': password,
      'captcha_challenge_field': captcha.trim(),
    };
    final response = await _request(
      'POST',
      _webUri('FollowTheRabbit'),
      headers: {HttpHeaders.refererHeader: 'https://bgm.tv/'},
      fields: fields,
      followRedirects: true,
    );
    _requireSuccess(response, '提交登录失败');
    final document = html.parse(response.body);
    final parsedUser = _parseUser(document);
    if (parsedUser == null) {
      final message =
          document.querySelector('#colunmNotice .text')?.text.trim();
      throw AuthException(
        message?.isNotEmpty == true ? message! : '登录失败，请检查账号、密码和验证码',
      );
    }

    await _completeLogin(parsedUser);
  }

  Future<String?> validAccessToken() async {
    final token = _token;
    if (token == null || _user == null) return null;
    if (!token.isExpired) return token.accessToken;
    return await refreshAccessToken() ? _token?.accessToken : null;
  }

  Future<bool> refreshAccessToken() async {
    final running = _refreshing;
    if (running != null) return running;
    final future = _refreshAccessTokenImpl();
    _refreshing = future;
    try {
      return await future;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> logout() async {
    _user = null;
    _token = null;
    await Future.wait([
      _cookies.clear(),
      _vault.delete(_userStorageKey),
      _vault.delete(_tokenStorageKey),
    ]);
    notifyListeners();
  }

  Future<void> _completeLogin(AuthUser parsedUser) async {
    final token = await _authorize(parsedUser.formHash);
    var user = parsedUser;
    try {
      final profileResponse = await _request(
        'GET',
        Uri.parse(
          'https://next.bgm.tv/p1/users/${Uri.encodeComponent(user.username)}',
        ),
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer ${token.accessToken}',
        },
      );
      if (profileResponse.statusCode >= 200 &&
          profileResponse.statusCode < 300) {
        final decoded = jsonDecode(profileResponse.body);
        if (decoded is Map) {
          final data =
              decoded['data'] is Map ? decoded['data'] as Map : decoded;
          user = user.mergeProfile(Map<String, dynamic>.from(data));
        }
      }
    } on Object {
      // The parsed web profile is enough to finish login if enrichment fails.
    }

    _user = user;
    _token = token;
    await _persistCredentials();
    notifyListeners();
  }

  Future<bool> _refreshAccessTokenImpl() async {
    final current = _token;
    final currentUser = _user;
    if (current == null || currentUser == null) return false;

    try {
      final refreshed = await _requestToken({
        'grant_type': 'refresh_token',
        'refresh_token': current.refreshToken,
      });
      _token = refreshed;
      await _persistCredentials();
      notifyListeners();
      return true;
    } on Object {
      if (currentUser.formHash.isEmpty) return false;
      try {
        _token = await _authorize(currentUser.formHash);
        await _persistCredentials();
        notifyListeners();
        return true;
      } on Object {
        return false;
      }
    }
  }

  Future<AuthToken> _authorize(String formHash) async {
    if (formHash.isEmpty) {
      throw const AuthException('登录成功，但未找到授权参数');
    }
    final authorizeUri = _webUri('oauth/authorize').replace(
      queryParameters: {
        'client_id': _appId,
        'response_type': 'code',
        'redirect_uri': _callback,
      },
    );
    final response = await _request(
      'POST',
      authorizeUri,
      fields: {'formhash': formHash, 'client_id': _appId, 'submit': '授权'},
      followRedirects: false,
    );
    final location = response.headers[HttpHeaders.locationHeader];
    final code = _authorizationCode(location);
    if (code.isEmpty) {
      final document = html.parse(response.body);
      final message =
          document.querySelector('#colunmNotice .text')?.text.trim();
      throw AuthException(
        message?.isNotEmpty == true ? message! : 'Bangumi OAuth 授权失败',
      );
    }
    return _requestToken({'grant_type': 'authorization_code', 'code': code});
  }

  Future<AuthToken> _requestToken(Map<String, String> grant) async {
    final response = await _request(
      'POST',
      _webUri('oauth/access_token'),
      fields: {
        ...grant,
        'redirect_uri': _callback,
        'state': '${DateTime.now().millisecondsSinceEpoch}',
        'client_id': _appId,
        'client_secret': _appSecret,
      },
    );
    _requireSuccess(response, '获取登录令牌失败');
    try {
      final decoded = Map<String, dynamic>.from(
        jsonDecode(response.body) as Map,
      );
      final token = AuthToken.fromJson({
        ...decoded,
        'saved_at': DateTime.now().millisecondsSinceEpoch,
      });
      if (token.accessToken.isEmpty || token.refreshToken.isEmpty) {
        throw const FormatException();
      }
      return token;
    } on Object {
      throw const AuthException('Bangumi 返回了无法识别的登录令牌');
    }
  }

  Future<http.Response> _request(
    String initialMethod,
    Uri initialUri, {
    Map<String, String>? headers,
    Map<String, String>? fields,
    bool followRedirects = true,
  }) async {
    var method = initialMethod;
    var uri = initialUri;
    var currentFields = fields;

    for (var redirects = 0; redirects <= 5; redirects++) {
      final request =
          http.Request(method, uri)
            ..followRedirects = false
            ..headers.addAll({
              HttpHeaders.acceptHeader:
                  'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
              HttpHeaders.acceptLanguageHeader: 'zh-CN,zh;q=0.9,en;q=0.5',
              HttpHeaders.userAgentHeader: _userAgent,
              HttpHeaders.cookieHeader: 'kira=4',
              ...?headers,
            });
      if (currentFields != null) request.bodyFields = currentFields;

      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamed);
      final location = response.headers[HttpHeaders.locationHeader];
      final isRedirect =
          response.statusCode >= 300 && response.statusCode < 400;
      if (!followRedirects || !isRedirect || location == null) return response;
      if (redirects == 5) throw const AuthException('登录跳转次数过多');

      uri = uri.resolve(location);
      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 303) {
        method = 'GET';
        currentFields = null;
      }
    }
    throw const AuthException('登录跳转失败');
  }

  AuthUser? _parseUser(Document document) {
    final welcome = document.querySelector('#main #header');
    if (welcome == null) return null;

    final avatar = document.querySelector('.idBadgerNeue a.avatar');
    final href = avatar?.attributes['href'] ?? '';
    final username = Uri.tryParse(href)?.pathSegments.lastOrNull ?? '';
    if (username.isEmpty) return null;

    final avatarStyle =
        avatar?.querySelector('span')?.attributes['style'] ?? '';
    final avatarUrl = _styleUrl(avatarStyle);
    final headerName = welcome.querySelector('a')?.text.trim() ?? '';
    final heading = welcome.querySelector('h1')?.text.trim() ?? '';
    final nickname =
        headerName.isNotEmpty
            ? headerName
            : (heading.isNotEmpty ? heading : username);
    final formHash =
        document
            .querySelector('input[name="formhash"]')
            ?.attributes['value']
            ?.trim() ??
        '';
    return AuthUser(
      username: username,
      nickname: nickname,
      avatarUrl: _absoluteUrl(avatarUrl),
      formHash: formHash,
    );
  }

  String _styleUrl(String style) {
    final match = RegExp(r'''url\(["']?(.+?)["']?\)''').firstMatch(style);
    return match?.group(1)?.trim() ?? '';
  }

  String _absoluteUrl(String value) {
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('/')) return 'https://bgm.tv$value';
    return value;
  }

  String _authorizationCode(String? location) {
    if (location == null || location.isEmpty) return '';
    final parsed = Uri.tryParse(location);
    final fromQuery = parsed?.queryParameters['code'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    return RegExp(r'[?&]code=([^&]+)').firstMatch(location)?.group(1)?.trim() ??
        '';
  }

  Uri _webUri(String path) => Uri.parse('https://bgm.tv/').resolve(path);

  void _requireSuccess(http.Response response, String message) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException('$message（${response.statusCode}）');
    }
  }

  Future<void> _persistCredentials() async {
    final user = _user;
    final token = _token;
    if (user == null || token == null) return;
    await Future.wait([
      _vault.write(_userStorageKey, jsonEncode(user.toJson())),
      _vault.write(_tokenStorageKey, jsonEncode(token.toJson())),
    ]);
  }

  Future<void> _clearCredentials() async {
    _user = null;
    _token = null;
    await Future.wait([
      _vault.delete(_userStorageKey),
      _vault.delete(_tokenStorageKey),
    ]);
  }
}
