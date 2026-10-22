import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';
import '../../core/paged.dart';
import '../../core/subject_detail_models.dart';

abstract interface class EpisodeProgressRepository {
  SessionScope get scope;
  Listenable get sessionChanges;
  Listenable get collectionChanges;
  Future<bool> isCollected(int subjectId, {bool fresh = false});
  Future<Paged<SubjectEpisode>> load(
    int subjectId, {
    int offset = 0,
    bool fresh = false,
  });
  Future<void> save(
    int subjectId,
    int episodeId,
    int status, {
    required SessionScope session,
    bool batch = false,
  });
}

abstract interface class EpisodeProgressFeature {
  EpisodeProgressRepository get episodeProgress;
}
