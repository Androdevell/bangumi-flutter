import 'package:flutter/foundation.dart';
import '../../core/community_models.dart';
import '../../core/models.dart';
import '../../core/json_utils.dart';

@immutable
class ComposeBlog {
  const ComposeBlog({
    required this.id,
    required this.title,
    required this.content,
    required this.user,
    this.createdAt,
  });
  factory ComposeBlog.fromJson(Map<String, dynamic> json) => ComposeBlog(
    id: (json['id'] as num).toInt(),
    title: '${json['title'] ?? ''}',
    content: '${json['content'] ?? ''}',
    user: CommunityUser.fromJson(
      Map<String, dynamic>.from(json['user'] as Map? ?? {}),
    ),
    createdAt: parseDate(json['createdAt']),
  );
  final int id;
  final String title, content;
  final CommunityUser user;
  final DateTime? createdAt;
}

@immutable
class ComposeBlogDetail {
  ComposeBlogDetail(
    this.blog,
    List<Subject> subjects,
    List<CommunityReply> comments, {
    Map<String, Object> errors = const {},
  }) : subjects = List.unmodifiable(subjects),
       comments = List.unmodifiable(comments),
       errors = Map.unmodifiable(errors);
  final ComposeBlog blog;
  final List<Subject> subjects;
  final List<CommunityReply> comments;
  final Map<String, Object> errors;
}
