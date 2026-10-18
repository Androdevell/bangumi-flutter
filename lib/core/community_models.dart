import 'package:flutter/foundation.dart';
import 'json_utils.dart' as dates;
import 'collection_labels.dart';

import 'models.dart';
import 'media/avatar_revision.dart';

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
      avatarUrl: AvatarRevision.resolve(_image(json['avatar'])),
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
  final DateTime? joinedAt;
  final bool isFriend;
  final UserStats stats;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CommunityUser &&
        other.id == id &&
        other.username == username &&
        other.nickname == nickname &&
        other.avatarUrl == avatarUrl &&
        other.sign == sign &&
        other.bio == bio &&
        other.location == location &&
        other.joinedAt == joinedAt &&
        other.isFriend == isFriend &&
        other.stats == stats;
  }

  @override
  int get hashCode => Object.hash(
    id,
    username,
    nickname,
    avatarUrl,
    sign,
    bio,
    location,
    joinedAt,
    isFriend,
    stats,
  );
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserStats &&
        other.subjects == subjects &&
        other.watched == watched &&
        other.friends == friends &&
        other.blogs == blogs &&
        other.groups == groups &&
        other.characters == characters &&
        other.persons == persons &&
        other.indexes == indexes;
  }

  @override
  int get hashCode => Object.hash(
    subjects,
    watched,
    friends,
    blogs,
    groups,
    characters,
    persons,
    indexes,
  );
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
    this.state = 0,
    this.relatedId = 0,
    this.creatorId = 0,
  });

  factory CommunityReply.fromJson(Map<String, dynamic> json) => CommunityReply(
    id: _int(json['id']),
    content:
        _int(json['state']) == 0
            ? _text(json['content'] ?? json['comment'])
            : '',
    user: CommunityUser.fromJson(_map(json['user'] ?? json['creator'])),
    createdAt: _date(json['createdAt'] ?? json['updatedAt']),
    replies: _list(json['replies']).map(CommunityReply.fromJson).toList(),
    reactions:
        _list(json['reactions']).map(CommunityReaction.fromJson).toList(),
    state: _int(json['state']),
    relatedId: _int(json['relatedID']),
    creatorId: _int(json['creatorID']),
  );

  final int id;
  final String content;
  final CommunityUser user;
  final DateTime? createdAt;
  final List<CommunityReply> replies;
  final List<CommunityReaction> reactions;
  final int state, relatedId, creatorId;
  bool get isVisible => state == 0;

  int get reactionCount => reactions.fold(0, (sum, item) => sum + item.count);
  bool likedBy(String username) => reactions.any(
    (reaction) => reaction.users.any((user) => user == username),
  );

  /// 值相等：供回复列表的 `didUpdateWidget` 判断数据是否真的变化。
  ///
  /// `replies` 是递归结构，`listEquals` 会逐层使用本类的 `==`，
  /// 因此嵌套回复的变化同样能被感知。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CommunityReply &&
        other.id == id &&
        other.content == content &&
        other.user == user &&
        other.createdAt == createdAt &&
        listEquals(other.replies, replies) &&
        listEquals(other.reactions, reactions) &&
        other.state == state &&
        other.relatedId == relatedId &&
        other.creatorId == creatorId;
  }

  @override
  int get hashCode => Object.hash(
    id,
    content,
    user,
    createdAt,
    Object.hashAll(replies),
    Object.hashAll(reactions),
    state,
    relatedId,
    creatorId,
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CommunityReaction &&
        other.value == value &&
        other.count == count &&
        listEquals(other.users, users);
  }

  @override
  int get hashCode => Object.hash(value, count, Object.hashAll(users));
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
      subtitle: collectionLabel(
        subjectType: _int(json['type']),
        status: _int(interest['type']),
      ),
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
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<CommunityReply> replies;
}

@immutable
class UserProfileData {
  const UserProfileData({
    this.sectionErrors = const {},
    required this.user,
    required this.timeline,
    required this.collections,
    required this.characters,
    required this.persons,
    required this.blogs,
    required this.indexes,
    required this.friends,
  });

  final Map<String, String> sectionErrors;
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
    this.sectionErrors = const {},
    required this.character,
    required this.works,
    required this.collectors,
    required this.comments,
    required this.indexes,
  });

  final Map<String, String> sectionErrors;
  final CharacterEntry character;
  final List<CharacterWork> works;
  final List<CommunityUser> collectors;
  final List<CommunityReply> comments;
  final List<UserContentItem> indexes;
}

@immutable
class PersonDetailData {
  const PersonDetailData({
    this.sectionErrors = const {},
    required this.person,
    required this.comments,
  });

  final Map<String, String> sectionErrors;
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

DateTime? _date(dynamic value) => dates.parseDate(value);
