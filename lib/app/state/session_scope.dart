import 'package:flutter/foundation.dart';

/// 请求所属的账号会话；令牌续期不等同于切换账号。
@immutable
class SessionScope {
  const SessionScope({
    required this.username,
    required this.accountId,
    required this.epoch,
  });

  final String username;
  final int accountId;
  final int epoch;

  @override
  bool operator ==(Object other) =>
      other is SessionScope &&
      other.username == username &&
      other.accountId == accountId &&
      other.epoch == epoch;

  @override
  int get hashCode => Object.hash(username, accountId, epoch);
}
