import '../../app/state/session_scope.dart';
import 'package:flutter/foundation.dart';
import '../../core/paged.dart';
import '../events/collection_changed.dart';
import '../models/collection_models.dart';

abstract interface class CollectionRepository {
  Stream<CollectionChanged> get changes;
  Listenable get sessionChanges;
  SessionScope get sessionScope;
  Future<Paged<ComposeCollectionItem>> query(
    CollectionQuery query, {
    int offset = 0,
    bool fresh = false,
  });
  Future<CollectionChanged> save(
    int subjectId,
    CollectionPatch patch, {
    required SessionScope scope,
  });
}
