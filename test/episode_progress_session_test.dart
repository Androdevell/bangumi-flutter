import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/app/state/session_scope.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/subject_detail_models.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';

class _SwitchableApi extends ApiClient {
  _SwitchableApi(http.Client client) : super(client: client);
  SessionScope active = const SessionScope(
    username: 'a',
    accountId: 1,
    epoch: 0,
  );
  @override
  SessionScope get sessionScope => active;
  @override
  bool get isLoggedIn => true;
}

class _DelayedEpisodeRepository extends RemoteBangumiRepository {
  _DelayedEpisodeRepository(ApiClient api, this.metadata)
    : super(apiClient: api);
  final Completer<SubjectEpisode> metadata;
  @override
  Future<SubjectEpisode> fetchEpisode(int id) => metadata.future;
}

void main() {
  test(
    'legacy progress keeps the original account across metadata await',
    () async {
      var requests = 0;
      final api = _SwitchableApi(
        MockClient((request) async {
          requests++;
          return http.Response('{"interest":{"type":3}}', 200);
        }),
      );
      final metadata = Completer<SubjectEpisode>();
      final repo = _DelayedEpisodeRepository(api, metadata);
      final save = repo.updateEpisodeProgress(3, 2);
      final expectation = expectLater(save, throwsA(isA<ApiException>()));
      api.active = const SessionScope(username: 'b', accountId: 2, epoch: 1);
      metadata.complete(SubjectEpisode.fromJson({'id': 3, 'subjectID': 8}));
      await expectation;
      expect(requests, 0);
      repo.close();
    },
  );
}
