import 'package:flutter/foundation.dart';
import '../../core/models.dart';
import '../../core/paged.dart';

@immutable
class ComposeTagQuery {
  const ComposeTagQuery(this.type, this.tag, {this.sort = 'rank'});
  final int type;
  final String tag, sort;
}

abstract interface class TagRepository {
  Future<Paged<Subject>> tagPage(ComposeTagQuery query, int page);
}
