import 'package:flutter/foundation.dart';

import 'models.dart';

@immutable
class CommunityUser {
  const CommunityUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.avatarUrl,
    required this.sign,
    required this.bio,
    required this.location,
    required this.joinedAt,
    required this.isFriend,
    required this.stats,
  });

  factory CommunityUser.fromJson(Map<String, dynamic> json) {
    final stats = _map(json['stats']);
    final subject = _map(stats['subject']);
    var subjectTotal = 0;
    var watched = 0;
    for (final value in subject.values) {
      final counts = _map(value);
      subjectTotal += counts.values.fold(0, (sum, item) => sum + _int(item));
      watched += _int(counts['2']);
    }
    return CommunityUser(
      id: _int(json['id']),
      username: _text(json['username']),
      nickname: _first([json['nickname'], json['username']]),
      avatarUrl: _image(json['avatar']),
      sign: _text(json['sign']),
      bio: _text(json['bio']),
      location: _text(json['location']),
      joinedAt: _date(json['joinedAt']),
      isFriend: json['isFriend'] == true,
      stats: UserStats(
        subjects: subjectTotal,
        watched: watched,
        friends: _int(stats['friend']),
        blogs: _int(stats['blog']),
        groups: _int(stats['group']),
        characters: _int(_map(stats['mono'])['character']),
        persons: _int(_map(stats['mono'])['person']),
        indexes: _int(_map(stats['index'])['create']),
      ),
    );
  }

  final int id;
  final String username;
  final String nickname;
  final String avatarUrl;
  final String sign;
  final String bio;
  final String location;
  final DateTime joinedAt;
  final bool isFriend;
  final UserStats stats;
}

@immutable
class UserStats {
  const UserStats({
    this.subjects = 0,
    this.watched = 0,
    this.friends = 0,
    this.blogs = 0,
    this.groups = 0,
    this.characters = 0,
    this.persons = 0,
    this.indexes = 0,
  });

  final int subjects;
  final int watched;
  final int friends;
  final int blogs;
  final int groups;
  final int characters;
  final int persons;
  final int indexes;
}

@immutable
class CommunityReply {
  const CommunityReply({
    required this.id,
    required this.content,
    required this.user,
    required this.createdAt,
    required this.replies,
    required this.reactions,
  });

  factory CommunityReply.fromJson(Map<String, dynamic> json) => CommunityReply(
    id: _int(json['id']),
    content: _text(json['content'] ?? json['comment']),
    user: CommunityUser.fromJson(_map(json['user'] ?? json['creator'])),
    createdAt: _date(json['createdAt'] ?? json['updatedAt']),
    replies: _list(json['replies']).map(CommunityReply.fromJson).toList(),
    reactions:
        _list(json['reactions']).map(CommunityReaction.fromJson).toList(),
  );

  final int id;
  final String content;
  final CommunityUser user;
  final DateTime createdAt;
  final List<CommunityReply> replies;
  final List<CommunityReaction> reactions;

  int get reactionCount => reactions.fold(0, (sum, item) => sum + item.count);
  bool likedBy(String username) => reactions.any(
    (reaction) => reaction.users.any((user) => user == username),
  );
}

@immutable
class CommunityReaction {
  const CommunityReaction({
    required this.value,
    required this.count,
    required this.users,
  });

  factory CommunityReaction.fromJson(
    Map<String, dynamic> json,
  ) => CommunityReaction(
    value: _text(json['value']).isEmpty ? '0' : _text(json['value']),
    count:
        _int(json['total']) == 0
            ? _list(json['users']).length
            : _int(json['total']),
    users: _list(json['users']).map((item) => _text(item['username'])).toList(),
  );

  final String value;
  final int count;
  final List<String> users;
}

@immutable
class UserContentItem {
  const UserContentItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.subjectType = 0,
    this.collectionType = 0,
    this.rate = 0,
    this.info = '',
  });

  factory UserContentItem.fromSubject(Map<String, dynamic> json) {
    final interest = _map(json['interest']);
    return UserContentItem(
      id: _int(json['id']),
      title: _first([json['nameCN'], json['name_cn'], json['name']]),
      subtitle: _collectionLabel(_int(interest['type'])),
      imageUrl: _image(json['images']),
      subjectType: _int(json['type']),
      collectionType: _int(interest['type']),
      rate: _int(interest['rate']),
      info: _text(json['info']),
    );
  }

  factory UserContentItem.fromMono(Map<String, dynamic> json) {
    final mono = _map(json['mono']).isEmpty ? json : _map(json['mono']);
    return UserContentItem(
      id: _int(mono['id']),
      title: _first([mono['nameCN'], mono['name_cn'], mono['name']]),
      subtitle: _text(mono['info']),
      imageUrl: _image(mono['images']),
    );
  }

  factory UserContentItem.fromBlog(Map<String, dynamic> json) {
    final entry = _map(json['entry']).isEmpty ? json : _map(json['entry']);
    return UserContentItem(
      id: _int(entry['id']),
      title: _first([entry['title'], '未命名日志']),
      subtitle: _text(entry['summary']),
      imageUrl: '',
    );
  }

  factory UserContentItem.fromIndex(Map<String, dynamic> json) =>
      UserContentItem(
        id: _int(json['id']),
        title: _first([json['title'], '未命名目录']),
        subtitle: '${_int(json['total'])} 项',
        imageUrl: '',
      );

  final int id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final int subjectType;
  final int collectionType;
  final int rate;
  final String info;
}

@immutable
class TopicDetailData {
  const TopicDetailData({
    required this.id,
    required this.type,
    required this.title,
    required this.groupName,
    required this.creator,
    required this.createdAt,
    required this.updatedAt,
    required this.replies,
  });

  factory TopicDetailData.fromJson(
    Map<String, dynamic> json, {
    required String type,
  }) {
    final group = _map(json['group']);
    final subject = _map(json['subject']);
    return TopicDetailData(
      id: _int(json['id']),
      type: type,
      title: _first([json['title'], subject['nameCN'], subject['name']]),
      groupName: _first([group['title'], subject['nameCN'], subject['name']]),
      creator: CommunityUser.fromJson(_map(json['creator'])),
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      replies: _list(json['replies']).map(CommunityReply.fromJson).toList(),
    );
  }

  final int id;
  final String type;
  final String title;
  final String groupName;
  final CommunityUser creator;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<CommunityReply> replies;
}

@immutable
class UserProfileData {
  const UserProfileData({
    required this.user,
    required this.timeline,
    required this.collections,
    required this.characters,
    required this.persons,
    required this.blogs,
    required this.indexes,
    required this.friends,
  });

  final CommunityUser user;
  final List<TimelineEntry> timeline;
  final List<UserContentItem> collections;
  final List<UserContentItem> characters;
  final List<UserContentItem> persons;
  final List<UserContentItem> blogs;
  final List<UserContentItem> indexes;
  final List<CommunityUser> friends;
}

@immutable
class CharacterDetailData {
  const CharacterDetailData({
    required this.character,
    required this.works,
    required this.collectors,
    required this.comments,
    required this.indexes,
  });

  final CharacterEntry character;
  final List<CharacterWork> works;
  final List<CommunityUser> collectors;
  final List<CommunityReply> comments;
  final List<UserContentItem> indexes;
}

@immutable
class PersonDetailData {
  const PersonDetailData({required this.person, required this.comments});

  final PersonEntry person;
  final List<CommunityReply> comments;
}

@immutable
class PersonEntry {
  const PersonEntry({
    required this.id,
    required this.name,
    required this.originalName,
    required this.imageUrl,
    required this.info,
    required this.summary,
    required this.collects,
    required this.careers,
    required this.infobox,
  });

  factory PersonEntry.fromJson(Map<String, dynamic> json) => PersonEntry(
    id: _int(json['id']),
    name: _first([json['nameCN'], json['name_cn'], json['name']]),
    originalName: _text(json['name']),
    imageUrl: _image(json['images']),
    info: _text(json['info']),
    summary: _text(json['summary']),
    collects: _int(json['collects']),
    careers:
        (json['career'] is List ? json['career'] as List : const [])
            .map(_text)
            .where((value) => value.isNotEmpty)
            .toList(),
    infobox:
        _list(json['infobox'])
            .map((item) {
              final values = _list(item['values'])
                  .map((value) {
                    final label = _text(value['k']);
                    final text = _text(value['v']);
                    return label.isEmpty ? text : '$label：$text';
                  })
                  .where((value) => value.isNotEmpty && !value.endsWith('：'));
              return '${_text(item['key'])}：${values.join('、')}';
            })
            .where((value) => !value.endsWith('：'))
            .toList(),
  );

  final int id;
  final String name;
  final String originalName;
  final String imageUrl;
  final String info;
  final String summary;
  final int collects;
  final List<String> careers;
  final List<String> infobox;
}

@immutable
class CharacterEntry {
  const CharacterEntry({
    required this.id,
    required this.name,
    required this.originalName,
    required this.imageUrl,
    required this.info,
    required this.summary,
    required this.collects,
    required this.collected,
    required this.infobox,
  });

  factory CharacterEntry.fromJson(Map<String, dynamic> json) => CharacterEntry(
    id: _int(json['id']),
    name: _first([json['nameCN'], json['name_cn'], json['name']]),
    originalName: _text(json['name']),
    imageUrl: _image(json['images']),
    info: _text(json['info']),
    summary: _text(json['summary']),
    collects: _int(json['collects']),
    collected: _int(json['collectedAt']) > 0,
    infobox:
        _list(json['infobox'])
            .map((item) {
              final values = _list(item['values'])
                  .map((value) => _text(value['v']))
                  .where((value) => value.isNotEmpty);
              return '${_text(item['key'])}：${values.join('、')}';
            })
            .where((value) => !value.endsWith('：'))
            .toList(),
  );

  final int id;
  final String name;
  final String originalName;
  final String imageUrl;
  final String info;
  final String summary;
  final int collects;
  final bool collected;
  final List<String> infobox;
}

@immutable
class CharacterWork {
  const CharacterWork({required this.subject, required this.actors});

  factory CharacterWork.fromJson(Map<String, dynamic> json) => CharacterWork(
    subject: Subject.fromJson(_map(json['subject'])),
    actors:
        _list(json['casts'])
            .map((cast) {
              final person = _map(cast['person']);
              return _first([
                person['nameCN'],
                person['name_cn'],
                person['name'],
              ]);
            })
            .where((name) => name.isNotEmpty)
            .toList(),
  );

  final Subject subject;
  final List<String> actors;
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? value.map((key, item) => MapEntry('$key', item)) : const {};
List<Map<String, dynamic>> _list(dynamic value) =>
    value is List
        ? value.whereType<Map>().map((item) => _map(item)).toList()
        : const [];
String _text(dynamic value) => value == null ? '' : value.toString().trim();
int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String _first(Iterable<dynamic> values) {
  for (final value in values) {
    final text = _text(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _image(dynamic value) {
  final images = _map(value);
  return _first([
    images['large'],
    images['common'],
    images['medium'],
    images['small'],
    images['grid'],
  ]);
}

DateTime _date(dynamic value) {
  if (value is num) {
    final millis =
        value.abs() < 100000000000 ? value.toInt() * 1000 : value.toInt();
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
  }
  return DateTime.tryParse(_text(value))?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

String _collectionLabel(int type) => switch (type) {
  1 => '想看',
  2 => '看过',
  3 => '在看',
  4 => '搁置',
  5 => '抛弃',
  _ => '',
};
