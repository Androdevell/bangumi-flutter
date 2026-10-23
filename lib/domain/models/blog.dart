import 'package:flutter/foundation.dart';
import '../../core/community_models.dart';
import '../../core/models.dart';
import '../../core/json_utils.dart';
import '../../core/text/bbcode_document.dart';

@immutable
class ComposeBlogPhoto {
  const ComposeBlogPhoto({required this.id, required this.target});
  factory ComposeBlogPhoto.fromJson(Map<String, dynamic> json) {
    final target = '${json['target'] ?? ''}';
    if (json['id'] is! num || BangumiBbCode.photoUrl(target) == null) {
      throw const FormatException('responseInvalid');
    }
    return ComposeBlogPhoto(id: (json['id'] as num).toInt(), target: target);
  }
  final int id;
  final String target;
  Uri get originalUrl => BangumiBbCode.photoUrl(target)!;
}

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
    List<ComposeBlogPhoto> photos = const [],
    this.photoTotal = 0,
  }) : subjects = List.unmodifiable(subjects),
       comments = List.unmodifiable(comments),
       errors = Map.unmodifiable(errors),
       photos = List.unmodifiable(photos);
  final ComposeBlog blog;
  final List<Subject> subjects;
  final List<CommunityReply> comments;
  final Map<String, Object> errors;
  final List<ComposeBlogPhoto> photos;
  final int photoTotal;
}
