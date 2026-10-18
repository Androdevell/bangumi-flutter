import 'package:flutter/foundation.dart';

abstract final class GroupMode {
  static const all = 'all', joined = 'joined', managed = 'managed';
  static const values = {all, joined, managed};
}

abstract final class GroupSort {
  static const updated = 'updated',
      created = 'created',
      members = 'members',
      posts = 'posts',
      topics = 'topics';
  static const values = {updated, created, members, posts, topics};
}

@immutable
class ComposeGroup {
  const ComposeGroup({
    required this.name,
    required this.title,
    required this.description,
    required this.icon,
    required this.members,
    required this.topics,
  });
  factory ComposeGroup.fromJson(Map<String, dynamic> json) {
    final icon = json['icon'];
    return ComposeGroup(
      name: '${json['name'] ?? ''}',
      title: '${json['title'] ?? json['name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      icon:
          icon is Map
              ? '${icon['large'] ?? icon['medium'] ?? icon['small'] ?? ''}'
              : icon is String
              ? icon
              : '',
      members: (json['members'] as num?)?.toInt() ?? 0,
      topics: (json['topics'] as num?)?.toInt() ?? 0,
    );
  }
  final String name, title, description, icon;
  final int members, topics;
}
