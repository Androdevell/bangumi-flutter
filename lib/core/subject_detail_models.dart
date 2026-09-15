import 'package:flutter/foundation.dart';

import 'models.dart';

@immutable
class SubjectDetailData {
  const SubjectDetailData({
    required this.subject,
    required this.infobox,
    required this.tags,
    required this.ratingDistribution,
    required this.collectionCounts,
    required this.episodes,
    required this.previews,
    required this.comments,
    required this.characters,
    required this.staffs,
    required this.relations,
    required this.indexes,
    required this.reviews,
    required this.topics,
    this.interestType = 0,
    this.interestRate = 0,
    this.interestComment = '',
    this.interestPrivate = false,
  });

  factory SubjectDetailData.fromSubjectJson({
    required Map<String, dynamic> json,
    required List<SubjectEpisode> episodes,
    required List<SubjectPreview> previews,
    required List<SubjectComment> comments,
    required List<SubjectCharacter> characters,
    required List<SubjectStaff> staffs,
    required List<SubjectRelation> relations,
    required List<SubjectIndex> indexes,
    required List<SubjectReview> reviews,
    required List<SubjectTopic> topics,
  }) {
    final rating = _map(json['rating']);
    final collection = _map(json['collection']);
    final interest = _map(json['interest']);
    return SubjectDetailData(
      subject: Subject.fromJson(json),
      infobox: _list(json['infobox']).map(SubjectInfoField.fromJson).toList(),
      tags: _list(json['tags']).map(SubjectTag.fromJson).toList(),
      ratingDistribution:
          rating['count'] is List
              ? (rating['count'] as List)
                  .map((value) => _integer(value))
                  .toList()
              : const [],
      collectionCounts: {
        for (final entry in collection.entries)
          _integer(entry.key): _integer(entry.value),
      },
      episodes: episodes,
      previews: previews,
      comments: comments,
      characters: characters,
      staffs: staffs,
      relations: relations,
      indexes: indexes,
      reviews: reviews,
      topics: topics,
      interestType: _integer(interest['type']),
      interestRate: _integer(interest['rate']),
      interestComment: _text(interest['comment']),
      interestPrivate: interest['private'] == true,
    );
  }

  final Subject subject;
  final List<SubjectInfoField> infobox;
  final List<SubjectTag> tags;
  final List<int> ratingDistribution;
  final Map<int, int> collectionCounts;
  final List<SubjectEpisode> episodes;
  final List<SubjectPreview> previews;
  final List<SubjectComment> comments;
  final List<SubjectCharacter> characters;
  final List<SubjectStaff> staffs;
  final List<SubjectRelation> relations;
  final List<SubjectIndex> indexes;
  final List<SubjectReview> reviews;
  final List<SubjectTopic> topics;
  final int interestType;
  final int interestRate;
  final String interestComment;
  final bool interestPrivate;
}

@immutable
class SubjectInfoField {
  const SubjectInfoField({required this.key, required this.values});

  factory SubjectInfoField.fromJson(Map<String, dynamic> json) =>
      SubjectInfoField(
        key: _text(json['key']),
        values:
            _list(json['values'])
                .map((value) => _text(value['v']))
                .where((value) => value.isNotEmpty)
                .toList(),
      );

  final String key;
  final List<String> values;
}

@immutable
class SubjectTag {
  const SubjectTag({required this.name, required this.count});

  factory SubjectTag.fromJson(Map<String, dynamic> json) =>
      SubjectTag(name: _text(json['name']), count: _integer(json['count']));

  final String name;
  final int count;
}

@immutable
class SubjectEpisode {
  const SubjectEpisode({
    required this.id,
    required this.sort,
    required this.name,
    required this.nameCn,
    required this.duration,
    required this.airdate,
    required this.commentCount,
    required this.description,
  });

  factory SubjectEpisode.fromJson(Map<String, dynamic> json) => SubjectEpisode(
    id: _integer(json['id']),
    sort: _decimal(json['sort']),
    name: _text(json['name']),
    nameCn: _text(json['nameCN'] ?? json['name_cn']),
    duration: _text(json['duration']),
    airdate: _text(json['airdate']),
    commentCount: _integer(json['comment']),
    description: _text(json['desc']),
  );

  final int id;
  final double sort;
  final String name;
  final String nameCn;
  final String duration;
  final String airdate;
  final int commentCount;
  final String description;

  String get title => nameCn.isNotEmpty ? nameCn : name;
}

@immutable
class SubjectPreview {
  const SubjectPreview({
    required this.id,
    required this.imageUrl,
    required this.largeImageUrl,
    required this.width,
    required this.height,
  });

  final String id;
  final String imageUrl;
  final String largeImageUrl;
  final int width;
  final int height;
}

@immutable
class SubjectComment {
  const SubjectComment({
    required this.id,
    required this.userName,
    required this.username,
    required this.avatarUrl,
    required this.rate,
    required this.comment,
    required this.updatedAt,
    required this.reactionCount,
    required this.reactedBy,
    required this.reactions,
    required this.reactionUsers,
  });

  factory SubjectComment.fromJson(Map<String, dynamic> json) {
    final user = _map(json['user']);
    return SubjectComment(
      id: _integer(json['id']),
      userName: _first([user['nickname'], user['username'], 'Bangumi 用户']),
      username: _text(user['username']),
      avatarUrl: _image(user['avatar']),
      rate: _integer(json['rate']),
      comment: _text(json['comment']),
      updatedAt: _date(json['updatedAt']),
      reactionCount: _list(json['reactions']).fold<int>(0, (sum, reaction) {
        final users = _list(reaction['users']);
        final total = _integer(reaction['total']);
        return sum + (total == 0 ? users.length : total);
      }),
      reactedBy:
          _list(json['reactions'])
              .expand((reaction) => _list(reaction['users']))
              .map((user) => _text(user['username']))
              .where((name) => name.isNotEmpty)
              .toSet(),
      reactions: {
        for (final reaction in _list(json['reactions']))
          _text(reaction['value']):
              _integer(reaction['total']) == 0
                  ? _list(reaction['users']).length
                  : _integer(reaction['total']),
      }..remove(''),
      reactionUsers: {
        for (final reaction in _list(json['reactions']))
          _text(reaction['value']):
              _list(reaction['users'])
                  .map((user) => _text(user['username']))
                  .where((name) => name.isNotEmpty)
                  .toSet(),
      }..remove(''),
    );
  }

  final int id;
  final String userName;
  final String username;
  final String avatarUrl;
  final int rate;
  final String comment;
  final DateTime updatedAt;
  final int reactionCount;
  final Set<String> reactedBy;
  final Map<String, int> reactions;
  final Map<String, Set<String>> reactionUsers;

  String? reactionBy(String username) {
    for (final reaction in reactionUsers.entries) {
      if (reaction.value.contains(username)) return reaction.key;
    }
    return null;
  }
}

@immutable
class SubjectCharacter {
  const SubjectCharacter({
    required this.id,
    required this.name,
    required this.originalName,
    required this.imageUrl,
    required this.info,
    required this.role,
    required this.casts,
  });

  factory SubjectCharacter.fromJson(Map<String, dynamic> json) {
    final character = _map(json['character']);
    final casts = _list(json['casts']);
    return SubjectCharacter(
      id: _integer(character['id']),
      name: _first([
        character['nameCN'],
        character['name_cn'],
        character['name'],
      ]),
      originalName: _text(character['name']),
      imageUrl: _image(character['images']),
      info: _text(character['info']),
      role: _characterRole(_integer(character['role'])),
      casts:
          casts
              .map((cast) => _map(cast['person']))
              .map(
                (person) => _first([
                  person['nameCN'],
                  person['name_cn'],
                  person['name'],
                ]),
              )
              .where((name) => name.isNotEmpty)
              .toList(),
    );
  }

  final int id;
  final String name;
  final String originalName;
  final String imageUrl;
  final String info;
  final String role;
  final List<String> casts;
}

@immutable
class SubjectStaff {
  const SubjectStaff({
    required this.id,
    required this.name,
    required this.originalName,
    required this.imageUrl,
    required this.info,
    required this.positions,
  });

  factory SubjectStaff.fromJson(Map<String, dynamic> json) {
    final staff = _map(json['staff']);
    final positions =
        _list(json['positions'])
            .map((position) {
              final type = _map(position['type']);
              final name = _first([type['cn'], type['jp'], type['en']]);
              final episodes = _text(position['appearEps']);
              return episodes.isEmpty ? name : '$name（$episodes）';
            })
            .where((value) => value.isNotEmpty)
            .toList();
    return SubjectStaff(
      id: _integer(staff['id']),
      name: _first([staff['nameCN'], staff['name_cn'], staff['name']]),
      originalName: _text(staff['name']),
      imageUrl: _image(staff['images']),
      info: _text(staff['info']),
      positions: positions,
    );
  }

  final int id;
  final String name;
  final String originalName;
  final String imageUrl;
  final String info;
  final List<String> positions;
}

@immutable
class SubjectRelation {
  const SubjectRelation({required this.subject, required this.relation});

  factory SubjectRelation.fromJson(Map<String, dynamic> json) =>
      SubjectRelation(
        subject: Subject.fromJson(_map(json['subject'])),
        relation: _first([
          _map(json['relation'])['cn'],
          _map(json['relation'])['jp'],
          _map(json['relation'])['en'],
        ]),
      );

  final Subject subject;
  final String relation;
}

@immutable
class SubjectIndex {
  const SubjectIndex({
    required this.id,
    required this.title,
    required this.total,
    required this.userName,
    required this.username,
    required this.avatarUrl,
    required this.updatedAt,
  });

  factory SubjectIndex.fromJson(Map<String, dynamic> json) {
    final user = _map(json['user']);
    return SubjectIndex(
      id: _integer(json['id']),
      title: _text(json['title']),
      total: _integer(json['total']),
      userName: _first([user['nickname'], user['username']]),
      username: _text(user['username']),
      avatarUrl: _image(user['avatar']),
      updatedAt: _date(json['updatedAt']),
    );
  }

  final int id;
  final String title;
  final int total;
  final String userName;
  final String username;
  final String avatarUrl;
  final DateTime updatedAt;
}

@immutable
class SubjectReview {
  const SubjectReview({
    required this.id,
    required this.title,
    required this.summary,
    required this.replies,
    required this.userName,
    required this.username,
    required this.avatarUrl,
    required this.updatedAt,
  });

  factory SubjectReview.fromJson(Map<String, dynamic> json) {
    final user = _map(json['user']);
    final entry = _map(json['entry']);
    return SubjectReview(
      id: _integer(entry['id'] ?? json['id']),
      title: _text(entry['title']),
      summary: _text(entry['summary']),
      replies: _integer(entry['replies']),
      userName: _first([user['nickname'], user['username']]),
      username: _text(user['username']),
      avatarUrl: _image(user['avatar']),
      updatedAt: _date(entry['updatedAt']),
    );
  }

  final int id;
  final String title;
  final String summary;
  final int replies;
  final String userName;
  final String username;
  final String avatarUrl;
  final DateTime updatedAt;
}

@immutable
class SubjectTopic {
  const SubjectTopic({
    required this.id,
    required this.title,
    required this.replies,
    required this.userName,
    required this.username,
    required this.avatarUrl,
    required this.updatedAt,
  });

  factory SubjectTopic.fromJson(Map<String, dynamic> json) {
    final creator = _map(json['creator']);
    return SubjectTopic(
      id: _integer(json['id']),
      title: _text(json['title']),
      replies: _integer(json['replyCount']),
      userName: _first([creator['nickname'], creator['username']]),
      username: _text(creator['username']),
      avatarUrl: _image(creator['avatar']),
      updatedAt: _date(json['updatedAt']),
    );
  }

  final int id;
  final String title;
  final int replies;
  final String userName;
  final String username;
  final String avatarUrl;
  final DateTime updatedAt;
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  return const {};
}

List<Map<String, dynamic>> _list(dynamic value) =>
    value is List
        ? value.whereType<Map>().map((item) => _map(item)).toList()
        : const [];

String _text(dynamic value) => value == null ? '' : '$value'.trim();
int _integer(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
double _decimal(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

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
    final milliseconds =
        value.abs() < 100000000000 ? value.toInt() * 1000 : value.toInt();
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
      isUtc: true,
    ).toLocal();
  }
  return DateTime.tryParse(_text(value))?.toLocal() ?? DateTime.now();
}

String _characterRole(int value) => switch (value) {
  1 => '主角',
  2 => '配角',
  3 => '客串',
  _ => '角色',
};
