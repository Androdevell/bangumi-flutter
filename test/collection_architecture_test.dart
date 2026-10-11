import 'dart:async';
import 'dart:convert';
import 'package:bangumi_flutter/app/state/session_scope.dart';
import 'package:bangumi_flutter/core/community_models.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/paged.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/domain/models/collection_models.dart';
import 'package:bangumi_flutter/features/collection/collection_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jsonResponse(Object? value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object> userJson(int count) => {
  'id': 7,
  'username': 'tester',
  'stats': {
    'subject': {
      '2': {'2': count},
    },
  },
};

UserContentItem item(int id) =>
    UserContentItem(id: id, title: 'item $id', subtitle: '', imageUrl: '');

void main() {
  test('ordinary timeline never sends SSE-only cat parameter', () async {
    late http.Request captured;
    final repository = RemoteBangumiRepository(
      apiClient: ApiClient(
        client: MockClient((request) async {
          captured = request;
          return jsonResponse([
            {'id': 1, 'cat': 5},
            {'id': 2, 'cat': 3},
          ]);
        }),
      ),
    );
    addTearDown(repository.close);
    final entries = await repository.fetchTimeline(category: 5);
    expect(captured.url.queryParameters, {'mode': 'all', 'limit': '20'});
    expect(entries.map((item) => item.id), [1]);
  });
  test('patch omits untouched fields, explicit clearing remains explicit', () {
    expect(CollectionPatch(rate: 0).toJson(), {'rate': 0});
    expect(CollectionPatch(comment: '', isPrivate: false, tags: []).toJson(), {
      'comment': '',
      'private': false,
      'tags': [],
    });
    final source = ['keep'];
    final patch = CollectionPatch(tags: source);
    source.clear();
    expect(patch.tags, ['keep']);
    expect(() => patch.tags!.add('x'), throwsUnsupportedError);
  });

  test(
    'personal query includes private collection endpoint and filters',
    () async {
      late http.Request captured;
      final api = MutableSessionApi(
        MockClient((request) async {
          captured = request;
          return jsonResponse({
            'data': [
              {
                'id': 4,
                'nameCN': 'book',
                'type': 1,
                'interest': {'type': 2},
              },
            ],
            'total': 101,
          });
        }),
      );
      final repository = RemoteBangumiRepository(apiClient: api);
      addTearDown(repository.close);
      final page = await repository.collections.query(
        const CollectionQuery(
          username: 'tester',
          subjectType: SubjectType.book,
          status: CollectionStatus.done,
        ),
        offset: 40,
      );
      expect(captured.url.path, '/p1/collections/subjects');
      expect(captured.url.queryParameters, {
        'limit': '40',
        'offset': '40',
        'subjectType': '1',
        'type': '2',
      });
      expect(page.total, 101);
      expect(page.items.single.id, 4);
      expect(page.nextOffset, 41);
    },
  );

  test(
    'public query uses public endpoint and omits all-filter magic values',
    () async {
      late http.Request captured;
      final repository = RemoteBangumiRepository(
        apiClient: MutableSessionApi(
          MockClient((request) async {
            captured = request;
            return jsonResponse({'data': [], 'total': 0});
          }),
        ),
      );
      addTearDown(repository.close);
      await repository.collections.query(
        const CollectionQuery(username: 'other'),
      );
      expect(captured.url.path, '/p1/users/other/collections/subjects');
      expect(captured.url.queryParameters, {'limit': '40', 'offset': '0'});
    },
  );

  test('controller loads all 245 items, not just a preloaded 100', () async {
    final offsets = <int>[];
    final repository = RemoteBangumiRepository(
      apiClient: MutableSessionApi(
        MockClient((request) async {
          final offset = int.parse(request.url.queryParameters['offset']!);
          offsets.add(offset);
          return jsonResponse({
            'data': [
              for (var i = offset; i < offset + 40 && i < 245; i++)
                {
                  'id': i + 1,
                  'name': 'item $i',
                  'type': 2,
                  'interest': {'type': 1},
                },
            ],
            'total': 245,
          });
        }),
      ),
    );
    addTearDown(repository.close);
    final controller = CollectionController(
      query: const CollectionQuery(username: 'tester'),
      load:
          (query, offset, fresh) =>
              repository.collections.query(query, offset: offset, fresh: fresh),
    );
    addTearDown(controller.dispose);
    while (controller.state.hasMore) {
      await controller.dispatch(const LoadCollections());
    }
    expect(controller.state.items.length, 245);
    expect(offsets, [0, 40, 80, 120, 160, 200, 240]);
    expect(controller.state.total, 245);
    expect(() => controller.state.items.clear(), throwsUnsupportedError);
  });

  test('quick filter changes discard older results and reset offset', () async {
    final pending = <Completer<Paged<UserContentItem>>>[];
    final queries = <CollectionQuery>[];
    final controller = CollectionController(
      query: const CollectionQuery(username: 'tester'),
      load: (query, offset, fresh) {
        expect(offset, 0);
        queries.add(query);
        final result = Completer<Paged<UserContentItem>>();
        pending.add(result);
        return result.future;
      },
    );
    addTearDown(controller.dispose);
    final first = controller.dispatch(const LoadCollections());
    final second = controller.dispatch(
      const ChangeCollectionFilter(
        CollectionQuery(
          username: 'tester',
          subjectType: SubjectType.book,
          status: CollectionStatus.done,
        ),
      ),
    );
    pending[1].complete(
      Paged(items: [item(2)], offset: 0, limit: 40, total: 1),
    );
    await second;
    pending[0].complete(
      Paged(items: [item(1)], offset: 0, limit: 40, total: 1),
    );
    await first;
    expect(controller.state.items.single.id, 2);
    expect(queries.last.subjectType, SubjectType.book);
  });

  test(
    'page failure preserves items, retry uses raw offset, duplicates dedupe',
    () async {
      var failed = false;
      final offsets = <int>[];
      final controller = CollectionController(
        query: const CollectionQuery(username: 'tester'),
        load: (_, offset, fresh) async {
          offsets.add(offset);
          if (offset == 0) {
            return Paged(
              items: [item(1), item(2)],
              offset: 0,
              limit: 2,
              total: 4,
            );
          }
          if (!failed) {
            failed = true;
            throw const ApiException('failed');
          }
          return Paged(
            items: [item(2), item(3)],
            offset: 2,
            limit: 2,
            total: 4,
          );
        },
      );
      addTearDown(controller.dispose);
      await controller.dispatch(const LoadCollections());
      await controller.dispatch(const LoadCollections());
      expect(controller.state.items.map((e) => e.id), [1, 2]);
      expect(controller.state.error, isNotNull);
      await controller.dispatch(const LoadCollections());
      expect(controller.state.items.map((e) => e.id), [1, 2, 3]);
      expect(offsets, [0, 2, 2]);
      expect(controller.state.offset, 4);
    },
  );

  test('failed refresh after last page can be retried', () async {
    var calls = 0;
    final controller = CollectionController(
      query: const CollectionQuery(username: 'tester'),
      load: (_, offset, fresh) async {
        if (++calls == 2) throw const ApiException('failed');
        return Paged(items: [item(calls)], offset: 0, limit: 40, total: 1);
      },
    );
    addTearDown(controller.dispose);
    await controller.dispatch(const LoadCollections());
    expect(controller.state.hasMore, isFalse);
    await controller.dispatch(const LoadCollections(refresh: true));
    expect(controller.state.items.single.id, 1);
    await controller.dispatch(const LoadCollections());
    expect(controller.state.items.single.id, 3);
  });

  test('dispose discards outstanding controller response', () async {
    final response = Completer<Paged<UserContentItem>>();
    final controller = CollectionController(
      query: const CollectionQuery(username: 'tester'),
      load: (_, __, ___) => response.future,
    );
    final loading = controller.dispatch(const LoadCollections());
    controller.dispose();
    response.complete(Paged(items: [item(1)], offset: 0, limit: 40));
    await loading;
    expect(controller.state.items, isEmpty);
  });

  test(
    'count ignores guessed wasCollected, dedupes writes, never times out to stale total',
    () async {
      var server = 9;
      final bodies = <Map>[];
      final repository = RemoteBangumiRepository(
        apiClient: MutableSessionApi(
          MockClient((request) async {
            if (request.method == 'PUT') {
              bodies.add(jsonDecode(request.body) as Map);
              return jsonResponse({});
            }
            if (request.url.path == '/p1/users/tester') {
              return jsonResponse(userJson(server));
            }
            return jsonResponse({'id': 42, 'interest': null});
          }),
        ),
      );
      addTearDown(repository.close);
      Future<void> save(int status) => repository.updateSubjectCollection(
        42,
        type: status,
        rate: 0,
        comment: '',
        isPrivate: false,
        wasCollected: true,
      );
      await save(CollectionStatus.wish);
      expect(repository.effectiveSubjectCollectionCount('tester', 9), 10);
      await save(CollectionStatus.wish);
      await save(CollectionStatus.done);
      expect(repository.effectiveSubjectCollectionCount('tester', 9), 10);
      expect(repository.users.isCollectionCountSyncing('tester'), isTrue);
      await repository.users.fetchUser('tester', fresh: true);
      expect(repository.effectiveSubjectCollectionCount('tester', 9), 10);
      server = 10;
      await repository.users.fetchUser('tester', fresh: true);
      expect(repository.effectiveSubjectCollectionCount('tester', 10), 10);
      expect(repository.users.isCollectionCountSyncing('tester'), isFalse);
      expect(bodies.every((body) => !body.containsKey('tags')), isTrue);
    },
  );

  test('rating edit preserves tags and only sends dirty field', () async {
    late Map body;
    final api = MutableSessionApi(
      MockClient((request) async {
        if (request.method == 'PUT') {
          body = jsonDecode(request.body) as Map;
          return jsonResponse({});
        }
        return jsonResponse({
          'id': 42,
          'interest': {
            'type': 2,
            'tags': ['keep'],
          },
        });
      }),
    );
    final repository = RemoteBangumiRepository(apiClient: api);
    addTearDown(repository.close);
    await repository.collections.save(
      42,
      CollectionPatch(rate: 8),
      scope: api.sessionScope,
    );
    expect(body, {'rate': 8});
  });

  test(
    'unsupported withdrawal fails before any request or success event',
    () async {
      var requests = 0;
      final repository = RemoteBangumiRepository(
        apiClient: MutableSessionApi(
          MockClient((_) async {
            requests++;
            return jsonResponse({});
          }),
        ),
      );
      addTearDown(repository.close);
      final events = <Object>[];
      final subscription = repository.collections.changes.listen(events.add);
      addTearDown(subscription.cancel);
      await expectLater(
        repository.collections.save(
          42,
          CollectionPatch(type: 0),
          scope: repository.collections.sessionScope,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(requests, 0);
      expect(events, isEmpty);
    },
  );

  test(
    'failed mutation publishes no confirmed event or count change',
    () async {
      final repository = RemoteBangumiRepository(
        apiClient: MutableSessionApi(
          MockClient(
            (request) async =>
                request.method == 'PUT'
                    ? jsonResponse({}, 400)
                    : jsonResponse({'id': 42, 'interest': null}),
          ),
        ),
      );
      addTearDown(repository.close);
      repository.effectiveSubjectCollectionCount('tester', 9);
      final events = <Object>[];
      final subscription = repository.collections.changes.listen(events.add);
      addTearDown(subscription.cancel);
      await expectLater(
        repository.collections.save(
          42,
          CollectionPatch(type: 1),
          scope: repository.collections.sessionScope,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(events, isEmpty);
      expect(repository.effectiveSubjectCollectionCount('tester', 9), 9);
    },
  );

  test('queued mutation never sends under changed account', () async {
    final pending = <Completer<http.Response>>[];
    final methods = <String>[];
    final api = MutableSessionApi(
      MockClient((request) {
        methods.add(request.method);
        final response = Completer<http.Response>();
        pending.add(response);
        return response.future;
      }),
    );
    addTearDown(api.close);
    final reads = [for (var i = 0; i < 3; i++) api.get('p1/test/$i')];
    final expectations =
        reads
            .map((read) => expectLater(read, throwsA(isA<ApiException>())))
            .toList();
    await Future<void>.delayed(Duration.zero);
    final write = api.put('p1/test/write', body: {'rate': 1});
    final writeExpectation = expectLater(write, throwsA(isA<ApiException>()));
    await Future<void>.delayed(Duration.zero);
    api.switchAccount('other');
    for (final response in pending) {
      response.complete(jsonResponse({}));
    }
    await Future.wait(expectations);
    await writeExpectation;
    expect(methods, ['GET', 'GET', 'GET']);
  });

  test(
    'form scope survives verification delay and cannot move to new account',
    () async {
      var calls = 0;
      final api = MutableSessionApi(
        MockClient((_) async {
          calls++;
          return jsonResponse({});
        }),
      );
      final repository = RemoteBangumiRepository(apiClient: api);
      addTearDown(repository.close);
      final formScope = api.sessionScope;
      api.switchAccount('other');
      await expectLater(
        repository.saveCollection(
          42,
          CollectionPatch(type: 1),
          expectedScope: formScope,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 0);
    },
  );

  test(
    'session change clears statistical baselines and confirmed ledger',
    () async {
      final api = MutableSessionApi(
        MockClient(
          (request) async =>
              request.method == 'PUT'
                  ? jsonResponse({})
                  : jsonResponse({'id': 42, 'interest': null}),
        ),
      );
      final repository = RemoteBangumiRepository(apiClient: api);
      addTearDown(repository.close);
      repository.effectiveSubjectCollectionCount('tester', 9);
      await repository.collections.save(
        42,
        CollectionPatch(type: 1),
        scope: api.sessionScope,
      );
      expect(repository.effectiveSubjectCollectionCount('tester', 9), 10);
      api.switchAccount('other');
      expect(repository.effectiveSubjectCollectionCount('tester', 9), 9);
      expect(repository.users.isCollectionCountSyncing('tester'), isFalse);
    },
  );

  test(
    'user summary reads just stats endpoint, not all profile tabs',
    () async {
      final paths = <String>[];
      final repository = RemoteBangumiRepository(
        apiClient: MutableSessionApi(
          MockClient((request) async {
            paths.add(request.url.path);
            return jsonResponse(userJson(9));
          }),
        ),
      );
      addTearDown(repository.close);
      await fetchUserSummary(repository, 'tester', fresh: true);
      await fetchUserSummary(repository, 'tester', fresh: true);
      expect(paths, ['/p1/users/tester', '/p1/users/tester']);
    },
  );

  test(
    'cache fresh read and targeted invalidation retain unrelated resources',
    () async {
      var calls = 0;
      final api = ApiClient(
        client: MockClient((_) async => jsonResponse(++calls)),
      );
      addTearDown(api.close);
      expect(await api.get('p1/a'), 1);
      expect(await api.get('p1/b'), 2);
      api.invalidateResources({'p1/a'});
      expect(await api.get('p1/b'), 2);
      expect(await api.get('p1/a'), 3);
      expect(await api.get('p1/b', fresh: true), 4);
    },
  );

  test('read-only POST retains cache; mutation POST invalidates it', () async {
    var reads = 0;
    final api = ApiClient(
      client: MockClient(
        (request) async => jsonResponse(request.method == 'GET' ? ++reads : 0),
      ),
    );
    addTearDown(api.close);
    await api.get('p1/a');
    await api.post(
      'p1/search/subjects',
      readOnly: true,
      body: {'keyword': 'x'},
    );
    expect(await api.get('p1/a'), 1);
    await api.post('p1/friends/tester');
    expect(await api.get('p1/a'), 2);
  });

  test(
    'injected shared client is borrowed and closes exactly once by owner',
    () {
      final transport = CountingClient();
      final api = ApiClient(client: transport, closeClient: false);
      api.close();
      api.close();
      expect(transport.closes, 0);
      transport.close();
      expect(transport.closes, 1);
    },
  );
}

class MutableSessionApi extends ApiClient {
  MutableSessionApi(http.Client client) : super(client: client);
  String account = 'tester';
  int epoch = 0;
  @override
  bool get isLoggedIn => account.isNotEmpty;
  @override
  String get currentUsername => account;
  @override
  SessionScope get sessionScope =>
      SessionScope(username: account, accountId: 7, epoch: epoch);
  void switchAccount(String username) {
    account = username;
    epoch++;
    (sessionChanges as ValueNotifier<SessionScope>).value = sessionScope;
    clearCache();
  }
}

class CountingClient extends http.BaseClient {
  int closes = 0;
  @override
  void close() {
    closes++;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();
}
