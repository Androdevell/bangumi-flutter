import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/paged.dart';
import '../../core/episode_types.dart';
import '../../core/subject_detail_models.dart';
import '../../domain/repositories/episode_progress_repository.dart';

class RemoteEpisodeProgressRepository implements EpisodeProgressRepository {
  RemoteEpisodeProgressRepository(this.api, {required this.onChanged});
  final ApiClient api;
  final VoidCallback onChanged;
  @override
  SessionScope get scope => api.sessionScope;
  @override
  Listenable get sessionChanges => api.sessionChanges;
  @override
  Future<Paged<SubjectEpisode>> load(
    int subjectId, {
    int offset = 0,
    bool fresh = false,
  }) async {
    final session = scope;
    final raw = await api.get(
      'p1/subjects/$subjectId/episodes',
      query: {'offset': '$offset', 'limit': '40'},
      fresh: fresh,
    );
    if (session != scope) throw const ApiException('commentSessionChanged');
    final rows = raw is Map ? raw['data'] ?? raw['result'] : raw;
    if (rows is! List) throw const ApiException('章节数据格式不正确');
    return Paged(
      items:
          rows
              .whereType<Map>()
              .map((r) => SubjectEpisode.fromJson(Map<String, dynamic>.from(r)))
              .toList(),
      offset: offset,
      limit: 40,
      total: raw is Map && raw['total'] is int ? raw['total'] as int : null,
    );
  }

  @override
  Future<void> save(
    int subjectId,
    int episodeId,
    int status, {
    required SessionScope session,
    bool batch = false,
  }) async {
    if (!api.isLoggedIn || session != scope) {
      throw const ApiException('commentSessionChanged');
    }
    if (episodeId <= 0 || !EpisodeStatus.values.contains(status)) {
      throw const ApiException('fieldInvalid');
    }
    await api.patch(
      'p1/collections/episodes/$episodeId',
      body: {'type': status, 'batch': batch},
      expectedScope: session,
      invalidatePaths: {
        'p1/subjects/$subjectId',
        'p1/collections/subjects',
        'p1/users/${Uri.encodeComponent(session.username)}',
      },
    );
    if (session != scope) {
      throw const ApiException('commentSessionChanged', outcomeUnknown: true);
    }
    api.invalidateResources({
      'p1/subjects/$subjectId',
      'p1/collections/subjects',
      'p1/users/${Uri.encodeComponent(session.username)}',
    });
    onChanged();
  }
}
