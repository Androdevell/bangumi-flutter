import 'package:flutter/material.dart';

@immutable
class Subject {
  const Subject({
    required this.id,
    required this.title,
    this.originalTitle = '',
    this.subtitle = '',
    this.summary = '',
    this.score = 0,
    this.ratingCount = 0,
    this.rank = 0,
    this.progress = 0,
    this.episodes = 0,
    this.imageUrl = '',
    this.type = 0,
    this.airDate = '',
  });

  factory Subject.fromJson(Map<String, dynamic> json) {
    final images = _map(json['images']);
    final rating = _map(json['rating']);
    final platform = _map(json['platform']);
    final airtime = _map(json['airtime']);
    final name = _string(json['name']);
    final nameCn = _string(json['name_cn'] ?? json['nameCN']);
    final info = _string(json['info']);
    final date = _string(json['airDate'] ?? airtime['date'] ?? json['date']);
    final platformName = _string(
      platform['typeCN'] ?? platform['type_cn'] ?? platform['type'],
    );

    return Subject(
      id: _integer(json['id']),
      title: nameCn.isNotEmpty ? nameCn : name,
      originalTitle: name,
      subtitle:
          platformName.isNotEmpty
              ? [
                platformName,
                date,
              ].where((item) => item.isNotEmpty).join(' · ')
              : (date.isNotEmpty ? date : _compact(info)),
      summary: _string(json['summary']),
      score: _decimal(rating['score']),
      ratingCount: _integer(rating['total']),
      rank: _integer(rating['rank']),
      progress: _integer(json['doing']),
      episodes: _integer(json['eps']),
      imageUrl: _firstNonEmpty([
        images['large'],
        images['common'],
        images['medium'],
        images['small'],
        images['grid'],
      ]),
      type: _integer(json['type']),
      airDate: date,
    );
  }

  final int id;
  final String title;
  final String originalTitle;
  final String subtitle;
  final String summary;
  final double score;
  final int ratingCount;
  final int rank;
  final int progress;
  final int episodes;
  final String imageUrl;
  final int type;
  final String airDate;

  bool get hasProgress => progress > 0 && episodes > 0;

  List<Color> get colors {
    const palettes = [
      [Color(0xFF2F80ED), Color(0xFF56CCF2)],
      [Color(0xFF6C5CE7), Color(0xFFE17055)],
      [Color(0xFF00A896), Color(0xFFF4A261)],
      [Color(0xFF264653), Color(0xFFE9C46A)],
    ];
    return palettes[id.abs() % palettes.length];
  }

  IconData get symbol => switch (type) {
    1 => Icons.menu_book_rounded,
    3 => Icons.album_rounded,
    4 => Icons.sports_esports_rounded,
    6 => Icons.movie_rounded,
    _ => Icons.live_tv_rounded,
  };

  String get typeLabel => switch (type) {
    1 => '书籍',
    2 => '动画',
    3 => '音乐',
    4 => '游戏',
    6 => '三次元',
    _ => '条目',
  };
}

@immutable
class TimelineEntry {
  const TimelineEntry({
    required this.id,
    required this.user,
    required this.action,
    required this.subject,
    required this.createdAt,
    this.avatarUrl = '',
    this.category = 0,
    this.username = '',
    this.reactionCount = 0,
    this.reactedBy = const {},
    this.reactions = const {},
    this.reactionUsers = const {},
    this.imageUrl = '',
    this.detail = '',
    this.sourceName = '',
    this.replies = 0,
    this.subjectId = 0,
  });

  factory TimelineEntry.fromJson(Map<String, dynamic> json) {
    final user = _map(json['user']);
    final memo = _map(json['memo']);
    final category = _integer(json['cat']);
    final type = _integer(json['type']);
    final reactions = _mapList(json['reactions']);
    final visual = _timelineVisual(memo, category);
    return TimelineEntry(
      id: _integer(json['id']),
      user: _firstNonEmpty([user['nickname'], user['username'], 'Bangumi 用户']),
      avatarUrl: _imageFromJson(user['avatar']),
      action: _timelineAction(category, type),
      subject: _timelineContent(memo, category),
      createdAt: _dateTime(json['createdAt'] ?? json['created_at']),
      category: category,
      username: _string(user['username']),
      reactionCount: reactions.fold<int>(0, (sum, reaction) {
        final users = _mapList(reaction['users']);
        final total = _integer(reaction['total']);
        return sum + (total == 0 ? users.length : total);
      }),
      reactedBy:
          reactions
              .expand((reaction) => _mapList(reaction['users']))
              .map((item) => _string(item['username']))
              .where((name) => name.isNotEmpty)
              .toSet(),
      reactions: {
        for (final reaction in reactions)
          _string(reaction['value']):
              _integer(reaction['total']) == 0
                  ? _mapList(reaction['users']).length
                  : _integer(reaction['total']),
      }..remove(''),
      reactionUsers: {
        for (final reaction in reactions)
          _string(reaction['value']):
              _mapList(reaction['users'])
                  .map((item) => _string(item['username']))
                  .where((name) => name.isNotEmpty)
                  .toSet(),
      }..remove(''),
      imageUrl: visual.$1,
      detail: visual.$2,
      subjectId: visual.$3,
      sourceName: _string(_map(json['source'])['name']),
      replies: _integer(json['replies']),
    );
  }

  final int id;
  final String user;
  final String avatarUrl;
  final String action;
  final String subject;
  final DateTime createdAt;
  final int category;
  final String username;
  final int reactionCount;
  final Set<String> reactedBy;
  final Map<String, int> reactions;
  final Map<String, Set<String>> reactionUsers;
  final String imageUrl;
  final String detail;
  final String sourceName;
  final int replies;
  final int subjectId;

  String? reactionBy(String username) {
    if (username.isEmpty) return null;
    for (final entry in reactionUsers.entries) {
      if (entry.value.contains(username)) return entry.key;
    }
    return null;
  }

  Color get color {
    const colors = [
      Color(0xFF2A9D8F),
      Color(0xFFE85D87),
      Color(0xFF6C5CE7),
      Color(0xFFF4A261),
      Color(0xFF2F80ED),
    ];
    return colors[id.abs() % colors.length];
  }

  String relativeTime([DateTime? now]) {
    final difference = (now ?? DateTime.now()).difference(createdAt);
    if (difference.inMinutes < 1) return '刚刚';
    if (difference.inMinutes < 60) return '${difference.inMinutes} 分钟前';
    if (difference.inHours < 24) return '${difference.inHours} 小时前';
    if (difference.inDays < 30) return '${difference.inDays} 天前';
    return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
  }
}

@immutable
class Topic {
  const Topic({
    required this.id,
    required this.type,
    required this.title,
    required this.group,
    required this.replies,
    required this.updatedAt,
    this.creatorName = '',
    this.creatorUsername = '',
    this.avatarUrl = '',
    this.imageUrl = '',
    this.subtitle = '',
    this.subjectId = 0,
    this.episodeSort = 0,
    this.episodeName = '',
  });

  factory Topic.fromJson(Map<String, dynamic> json) {
    final group = _map(json['group']);
    final subject = _map(json['subject']);
    final creator = _map(json['creator']);
    final episode = _map(json['episode']);
    final type = _string(json['type']);
    final episodeSort = _decimal(episode['sort']);
    final episodeName = _firstNonEmpty([
      episode['nameCN'],
      episode['name_cn'],
      episode['name'],
    ]);
    final fallbackTitle =
        type == 'episode'
            ? 'Ep.${episodeSort.toString().replaceAll(RegExp(r'\.0$'), '')}${episodeName.isEmpty ? '' : '  $episodeName'}'
            : _firstNonEmpty([json['nameCN'], json['name_cn'], json['name']]);
    return Topic(
      id: _integer(json['id']),
      type: type,
      title: _firstNonEmpty([json['title'], fallbackTitle]),
      group: _firstNonEmpty([
        group['title'],
        group['name'],
        subject['name_cn'],
        subject['nameCN'],
        subject['name'],
        creator['nickname'],
        'Bangumi',
      ]),
      replies: _integer(json['replyCount'] ?? json['comment']),
      updatedAt: _dateTime(json['updatedAt'] ?? json['updated_at']),
      creatorName: _firstNonEmpty([creator['nickname'], creator['username']]),
      creatorUsername: _string(creator['username']),
      avatarUrl: _imageFromJson(creator['avatar']),
      imageUrl: _firstNonEmpty([
        _imageFromJson(subject['images']),
        _imageFromJson(json['images']),
        _imageFromJson(group['icon']),
      ]),
      subtitle: _firstNonEmpty([episodeName, subject['info'], json['info']]),
      subjectId: _integer(subject['id']),
      episodeSort: episodeSort,
      episodeName: episodeName,
    );
  }

  final int id;
  final String type;
  final String title;
  final String group;
  final int replies;
  final DateTime updatedAt;
  final String creatorName;
  final String creatorUsername;
  final String avatarUrl;
  final String imageUrl;
  final String subtitle;
  final int subjectId;
  final double episodeSort;
  final String episodeName;

  String get typeLabel => switch (type) {
    'group' => '小组',
    'my_group' => '我的小组',
    'subject' => '条目',
    'episode' || 'ep' => '章节',
    'character' => '角色',
    'person' => '人物',
    _ => '讨论',
  };

  String relativeTime([DateTime? now]) {
    final difference = (now ?? DateTime.now()).difference(updatedAt);
    if (difference.inMinutes < 1) return '刚刚';
    if (difference.inMinutes < 60) return '${difference.inMinutes} 分钟前';
    if (difference.inHours < 24) return '${difference.inHours} 小时前';
    return '${difference.inDays} 天前';
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  return const {};
}

List<Map<String, dynamic>> _mapList(dynamic value) =>
    value is List
        ? value.whereType<Map>().map((item) => _map(item)).toList()
        : const [];

String _string(dynamic value) => value == null ? '' : value.toString().trim();
int _integer(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
double _decimal(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

String _firstNonEmpty(Iterable<dynamic> values) {
  for (final value in values) {
    final text = _string(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _compact(String value) {
  final line = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return line.length > 42 ? '${line.substring(0, 42)}…' : line;
}

DateTime _dateTime(dynamic value) {
  if (value is num) {
    final milliseconds =
        value.abs() < 100000000000 ? value.toInt() * 1000 : value.toInt();
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
      isUtc: true,
    ).toLocal();
  }
  return DateTime.tryParse(_string(value))?.toLocal() ?? DateTime.now();
}

String _imageFromJson(dynamic value) {
  final images = _map(value);
  return _firstNonEmpty([
    images['large'],
    images['common'],
    images['medium'],
    images['small'],
    images['grid'],
  ]);
}

String _timelineAction(int category, int type) {
  if (category == 3) {
    const actions = {
      1: '想读',
      2: '想看',
      3: '想听',
      4: '想玩',
      5: '读过',
      6: '看过',
      7: '听过',
      8: '玩过',
      9: '在读',
      10: '在看',
      11: '在听',
      12: '在玩',
      13: '搁置了',
      14: '抛弃了',
    };
    return actions[type] ?? '收藏了';
  }
  return switch (category) {
    1 => '更新了日常',
    2 => '编辑了维基',
    4 => switch (type) {
      1 => '想看',
      2 => '看过',
      3 => '抛弃了',
      _ => '更新了进度',
    },
    5 => switch (type) {
      0 => '更新了签名',
      1 => '发表了吐槽',
      2 => '修改了昵称',
      _ => '更新了状态',
    },
    6 => '发表了日志',
    7 => '更新了目录',
    8 => '收藏了人物',
    _ => '更新了动态',
  };
}

String _timelineContent(Map<String, dynamic> memo, int category) {
  if (category == 5) {
    final status = _map(memo['status']);
    return _firstNonEmpty([status['tsukkomi'], status['sign'], '']);
  }
  if (category == 3 && memo['subject'] is List) {
    final names =
        (memo['subject'] as List)
            .map((item) {
              final subject = _map(_map(item)['subject']);
              return _firstNonEmpty([
                subject['name_cn'],
                subject['nameCN'],
                subject['name'],
              ]);
            })
            .where((name) => name.isNotEmpty)
            .take(3)
            .toList();
    if (names.isNotEmpty) return names.join('、');
  }
  final found = _findTimelineText(memo);
  return found.isEmpty ? '一条 Bangumi 动态' : found;
}

(String, String, int) _timelineVisual(Map<String, dynamic> memo, int category) {
  Map<String, dynamic> subject = const {};
  var detail = '';
  if (category == 3 && memo['subject'] is List) {
    final items = _mapList(memo['subject']);
    if (items.isNotEmpty) {
      subject = _map(items.first['subject']);
      detail = _firstNonEmpty([items.first['comment'], subject['info']]);
    }
  } else if (category == 4) {
    final progress = _map(memo['progress']);
    final entry =
        _map(progress['single']).isNotEmpty
            ? _map(progress['single'])
            : _map(progress['batch']);
    subject = _map(entry['subject']);
    final episode = _map(entry['episode']);
    final sort = _decimal(episode['sort']);
    final episodeName = _firstNonEmpty([
      episode['nameCN'],
      episode['name_cn'],
      episode['name'],
    ]);
    if (sort > 0 || episodeName.isNotEmpty) {
      detail =
          'Ep.${sort.toString().replaceAll(RegExp(r'\.0$'), '')}${episodeName.isEmpty ? '' : ' · $episodeName'}';
    }
  } else {
    subject = _map(_map(memo['wiki'])['subject']);
  }
  return (
    _imageFromJson(subject['images']),
    _compact(detail),
    _integer(subject['id']),
  );
}

String _findTimelineText(dynamic value) {
  if (value is Map) {
    const priority = [
      'title',
      'name_cn',
      'nameCN',
      'name',
      'comment',
      'content',
      'tsukkomi',
      'sign',
    ];
    for (final key in priority) {
      final text = _string(value[key]);
      if (text.isNotEmpty && text != '{}') return _compact(text);
    }
    for (final child in value.values) {
      final text = _findTimelineText(child);
      if (text.isNotEmpty) return text;
    }
  } else if (value is List) {
    for (final child in value) {
      final text = _findTimelineText(child);
      if (text.isNotEmpty) return text;
    }
  }
  return '';
}
