import 'package:flutter/foundation.dart';
import '../../core/community_models.dart';

abstract final class CollectionStatus {
  static const wish = 1;
  static const done = 2;
  static const doing = 3;
  static const onHold = 4;
  static const dropped = 5;
  static const values = [wish, done, doing, onHold, dropped];
}

abstract final class SubjectType {
  static const book = 1;
  static const anime = 2;
  static const music = 3;
  static const game = 4;
  static const real = 6;
  static const values = [book, anime, music, game, real];
}

@immutable
class CollectionQuery {
  const CollectionQuery({
    required this.username,
    this.subjectType,
    this.status,
  });

  final String username;
  final int? subjectType;
  final int? status;
}

/// null 表示不修改；空字符串、0、false、空标签数组表示明确设置。
@immutable
class CollectionPatch {
  CollectionPatch({
    this.type,
    this.rate,
    this.comment,
    this.isPrivate,
    List<String>? tags,
  }) : tags = tags == null ? null : List.unmodifiable(tags);

  final int? type;
  final int? rate;
  final String? comment;
  final bool? isPrivate;
  final List<String>? tags;

  Map<String, Object> toJson() => {
    if (type != null) 'type': type!,
    if (rate != null) 'rate': rate!,
    if (comment != null) 'comment': comment!,
    if (isPrivate != null) 'private': isPrivate!,
    if (tags != null) 'tags': tags!,
  };
}

@immutable
class ComposeCollectionItem extends UserContentItem {
  ComposeCollectionItem(UserContentItem item)
    : super(
        id: item.id,
        title: item.title,
        subtitle: item.subtitle,
        imageUrl: item.imageUrl,
        subjectType: item.subjectType,
        collectionType: item.collectionType,
        rate: item.rate,
        info: item.info,
      );
}
