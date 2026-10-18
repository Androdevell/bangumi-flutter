import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../../core/paged.dart';
import '../../core/models.dart';
import '../../domain/models/group_models.dart';
import '../../domain/repositories/group_repository.dart';

class RemoteGroupRepository implements GroupRepository {
  RemoteGroupRepository(this.api);
  final ApiClient api;
  @override
  Listenable get sessionChanges => api.sessionChanges;
  @override
  bool get isLoggedIn => api.isLoggedIn;
  @override
  Future<Paged<ComposeGroup>> list({
    String mode = GroupMode.all,
    String sort = GroupSort.updated,
    int offset = 0,
    bool fresh = false,
  }) async {
    if (!GroupMode.values.contains(mode) ||
        !GroupSort.values.contains(sort) ||
        offset < 0) {
      throw const ApiException('fieldInvalid');
    }
    if (mode != GroupMode.all && !isLoggedIn) {
      throw const ApiException('loginRequired');
    }
    final scope = api.sessionScope;
    final raw = await api.get(
      'p1/groups',
      query: {'mode': mode, 'sort': sort, 'offset': '$offset', 'limit': '20'},
      fresh: fresh,
    );
    if (scope != api.sessionScope) {
      throw const ApiException('commentSessionChanged');
    }
    return _page(raw, offset, ComposeGroup.fromJson);
  }

  @override
  Future<ComposeGroup> detail(String name) async {
    final raw = await api.get(
      'p1/groups/${Uri.encodeComponent(name)}',
      fresh: true,
    );
    if (raw is! Map || raw['name'] != name) {
      throw const ApiException('fieldInvalid');
    }
    return ComposeGroup.fromJson(Map<String, dynamic>.from(raw));
  }

  @override
  Future<Paged<Topic>> topics(
    String name, {
    int offset = 0,
    bool fresh = false,
  }) async {
    final raw = await api.get(
      'p1/groups/${Uri.encodeComponent(name)}/topics',
      query: {'offset': '$offset', 'limit': '20'},
      fresh: fresh,
    );
    return _page(
      raw,
      offset,
      (row) => Topic.fromJson({...row, 'type': 'group'}),
    );
  }

  Paged<T> _page<T>(
    dynamic raw,
    int offset,
    T Function(Map<String, dynamic>) convert,
  ) {
    final rows = raw is Map ? raw['data'] ?? raw['result'] : raw;
    if (rows is! List) throw const ApiException('fieldInvalid');
    return Paged(
      items:
          rows
              .whereType<Map>()
              .map((row) => convert(Map<String, dynamic>.from(row)))
              .toList(),
      offset: offset,
      limit: 20,
      total: raw is Map && raw['total'] is int ? raw['total'] as int : null,
    );
  }
}
