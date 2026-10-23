import 'package:flutter/foundation.dart';

@immutable
class ComposeNotice {
  const ComposeNotice({
    required this.id,
    required this.type,
    required this.title,
    required this.username,
    required this.nickname,
    required this.mainId,
    required this.relatedId,
    required this.unread,
    this.createdAt,
  });
  final int id, type, mainId, relatedId;
  final String title, username, nickname;
  final bool unread;
  final DateTime? createdAt;
  factory ComposeNotice.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] is Map ? json['sender'] as Map : const {};
    int number(Object? value) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    final timestamp = number(json['createdAt']);
    return ComposeNotice(
      id: number(json['id']),
      type: number(json['type']),
      title: '${json['title'] ?? ''}',
      username: '${sender['username'] ?? sender['id'] ?? ''}',
      nickname: '${sender['nickname'] ?? sender['username'] ?? ''}',
      mainId: number(json['mainID']),
      relatedId: number(json['relatedID']),
      unread: json['unread'] == true,
      createdAt:
          timestamp > 0 && timestamp < 8640000000000
              ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
              : null,
    );
  }
  ComposeNotice read() => ComposeNotice(
    id: id,
    type: type,
    title: title,
    username: username,
    nickname: nickname,
    mainId: mainId,
    relatedId: relatedId,
    unread: false,
    createdAt: createdAt,
  );

  String get labelKey => switch (type) {
    14 => 'noticeFriend',
    15 => 'noticeFriendAccepted',
    23 || 24 || 25 || 26 || 28 || 29 || 30 => 'noticeMention',
    >= 35 && <= 50 => 'noticeRevision',
    _ => 'noticeReply',
  };

  /// 地址仅由已知类型和数值 ID 生成，不信任服务器正文内的任意跳转。
  Uri get target {
    final path =
        mainId > 0
            ? switch (type) {
              1 || 2 || 23 => '/group/topic/$mainId',
              3 || 4 || 24 => '/subject/topic/$mainId',
              5 || 6 || 25 => '/character/$mainId',
              13 || 26 => '/person/$mainId',
              10 || 30 => '/ep/$mainId',
              7 || 8 || 29 => '/blog/$mainId',
              11 || 12 => '/index/$mainId',
              14 || 15 => '/user/$mainId',
              22 || 28 => '/user/${Uri.encodeComponent(username)}/timeline',
              _ => '/notify/all',
            }
            : '/notify/all';
    return Uri.https('bgm.tv', path);
  }
}

@immutable
class ComposeNoticeBatch {
  ComposeNoticeBatch(List<ComposeNotice> items, this.total)
    : items = List.unmodifiable(items);
  final List<ComposeNotice> items;
  final int total;
}
