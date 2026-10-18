import 'package:flutter/foundation.dart';
import '../../core/paged.dart';
import '../../core/models.dart';
import '../models/group_models.dart';

abstract interface class GroupRepository {
  Listenable get sessionChanges;
  bool get isLoggedIn;
  Future<Paged<ComposeGroup>> list({
    String mode = GroupMode.all,
    String sort = GroupSort.updated,
    int offset = 0,
    bool fresh = false,
  });
  Future<ComposeGroup> detail(String name);
  Future<Paged<Topic>> topics(
    String name, {
    int offset = 0,
    bool fresh = false,
  });
}

abstract interface class GroupFeature {
  GroupRepository get groups;
}
