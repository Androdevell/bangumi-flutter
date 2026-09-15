class LoginChallenge {
  const LoginChallenge(this.hiddenFields);

  final Map<String, String> hiddenFields;
}

class AuthUser {
  const AuthUser({
    required this.username,
    required this.nickname,
    required this.formHash,
    this.id = 0,
    this.avatarUrl = '',
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: _int(json['id']),
    username: _text(json['username']),
    nickname: _text(json['nickname']),
    avatarUrl: _image(json['avatar'] ?? json['images']),
    formHash: _text(json['formHash']),
  );

  final int id;
  final String username;
  final String nickname;
  final String avatarUrl;
  final String formHash;

  String get displayName => nickname.isEmpty ? username : nickname;

  AuthUser mergeProfile(Map<String, dynamic> json) {
    final profile = AuthUser.fromJson({...json, 'formHash': formHash});
    return AuthUser(
      id: profile.id == 0 ? id : profile.id,
      username: profile.username.isEmpty ? username : profile.username,
      nickname: profile.nickname.isEmpty ? nickname : profile.nickname,
      avatarUrl: profile.avatarUrl.isEmpty ? avatarUrl : profile.avatarUrl,
      formHash: formHash,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'nickname': nickname,
    'avatar': avatarUrl,
    'formHash': formHash,
  };
}

class AuthToken {
  const AuthToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.savedAt,
    this.tokenType = 'Bearer',
    this.userId = 0,
  });

  factory AuthToken.fromJson(Map<String, dynamic> json) => AuthToken(
    accessToken: _text(json['access_token']),
    refreshToken: _text(json['refresh_token']),
    expiresIn: _int(json['expires_in']),
    tokenType: _text(json['token_type']),
    userId: _int(json['user_id']),
    savedAt: DateTime.fromMillisecondsSinceEpoch(
      _int(json['saved_at'] ?? json['saveAt']),
    ),
  );

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final String tokenType;
  final int userId;
  final DateTime savedAt;

  bool get isExpired =>
      accessToken.isEmpty ||
      refreshToken.isEmpty ||
      DateTime.now().isAfter(
        savedAt
            .add(Duration(seconds: expiresIn))
            .subtract(const Duration(minutes: 1)),
      );

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_in': expiresIn,
    'token_type': tokenType,
    'user_id': userId,
    'saved_at': savedAt.millisecondsSinceEpoch,
  };
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _text(dynamic value) => value == null ? '' : value.toString().trim();
int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

String _image(dynamic value) {
  if (value is String) return value.trim();
  if (value is! Map) return '';
  for (final key in const ['large', 'common', 'medium', 'small']) {
    final candidate = _text(value[key]);
    if (candidate.isNotEmpty) return candidate;
  }
  return '';
}
