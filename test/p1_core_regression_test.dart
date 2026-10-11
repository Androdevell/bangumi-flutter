import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bangumi_flutter/core/collection_labels.dart';
import 'package:bangumi_flutter/core/community_models.dart';
import 'package:bangumi_flutter/core/json_utils.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/core/network/android_image_file_service.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/network/platform_http_client.dart';
import 'package:bangumi_flutter/core/paged.dart';
import 'package:bangumi_flutter/core/paged_controller.dart';
import 'package:bangumi_flutter/core/subject_detail_models.dart';
import 'package:bangumi_flutter/core/update/app_update_service.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jsonResponse(Object value, [int code = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(value)), code);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all 20 collection labels match their media types', () {
    for (final entry in {1: '读', 2: '看', 3: '听', 4: '玩'}.entries) {
      for (var status = 1; status <= 5; status++) {
        final expected =
            [
              '想${entry.value}',
              '${entry.value}过',
              '在${entry.value}',
              '搁置',
              '抛弃',
            ][status - 1];
        expect(
          collectionLabel(subjectType: entry.key, status: status),
          expected,
        );
        expect(
          UserContentItem.fromSubject({
            'type': entry.key,
            'interest': {'type': status},
            'id': 1,
          }).subtitle,
          contains(expected),
        );
      }
    }
  });
  test('dates are shared across all models without invented values', () {
    for (final value in [
      null,
      '',
      'invalid',
      0,
      -1,
      double.nan,
      double.infinity,
    ]) {
      expect(parseDate(value), isNull);
      expect(CommunityReply.fromJson({'createdAt': value}).createdAt, isNull);
      expect(SubjectComment.fromJson({'updatedAt': value}).updatedAt, isNull);
      expect(TimelineEntry.fromJson({'createdAt': value}).createdAt, isNull);
    }
    final expected = DateTime.utc(2026, 1, 1);
    for (final value in [
      1767225600,
      1767225600000,
      '1767225600',
      '1767225600000',
      '2026-01-01T00:00:00Z',
    ]) {
      expect(parseDate(value)?.toUtc(), expected);
    }
    expect(dateText(null), '—');
    expect(relativeTime(null), '—');
    expect(
      relativeTime(expected, now: expected.subtract(const Duration(days: 1))),
      '2026-01-01',
    );
  });
  test(
    'GET single-flight, TTL, canonical parameters and invalidation',
    () async {
      var calls = 0;
      var now = DateTime.utc(2026);
      final api = ApiClient(
        clock: () => now,
        client: MockClient((request) async {
          calls++;
          await Future<void>.delayed(Duration.zero);
          return jsonResponse({'ok': true});
        }),
      );
      addTearDown(api.close);
      await Future.wait([
        api.get('same', query: {'a': '1', 'b': '2'}),
        api.get('same', query: {'b': '2', 'a': '1'}),
      ]);
      await api.get('same', query: {'a': '1', 'b': '2'});
      expect(calls, 1);
      now = now.add(const Duration(minutes: 6));
      await api.get('same', query: {'a': '1', 'b': '2'});
      expect(calls, 2);
      api.clearCache();
      await api.get('same', query: {'a': '1', 'b': '2'});
      expect(calls, 3);
    },
  );
  for (final header in ['2', 'Thu, 01 Jan 2026 00:00:02 GMT']) {
    test('429 respects Retry-After $header', () async {
      var calls = 0;
      final waits = <Duration>[];
      final api = ApiClient(
        clock: () => DateTime.utc(2026),
        delay: (d) async {
          waits.add(d);
        },
        client: MockClient((request) async {
          calls++;
          return calls == 1
              ? http.Response('', 429, headers: {'retry-after': header})
              : jsonResponse([]);
        }),
      );
      addTearDown(api.close);
      expect(await api.get('limited'), []);
      expect(calls, 2);
      expect(waits, [const Duration(seconds: 2)]);
    });
  }
  test('long Retry-After is surfaced without retrying early', () async {
    var calls = 0;
    final api = ApiClient(
      delay: (_) async => fail('must not retry early'),
      client: MockClient((_) async {
        calls++;
        return http.Response('', 429, headers: {'retry-after': '60'});
      }),
    );
    addTearDown(api.close);
    await expectLater(
      api.get('long'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'code', 429)),
    );
    expect(calls, 1);
  });
  test('GET transient failure retries but mutation never does', () async {
    var gets = 0;
    var puts = 0;
    final api = ApiClient(
      delay: (_) async {},
      client: MockClient((request) async {
        if (request.method == 'GET') {
          if (++gets == 1) throw http.ClientException('temporary');
          return jsonResponse([]);
        }
        puts++;
        return jsonResponse({'message': '请求失败'}, 503);
      }),
    );
    addTearDown(api.close);
    await api.get('transient');
    await expectLater(api.put('mutation'), throwsA(isA<ApiException>()));
    expect(gets, 2);
    expect(puts, 1);
  });
  test('at most three API responses are in flight', () async {
    var active = 0;
    var maximum = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        active++;
        if (active > maximum) maximum = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return jsonResponse([]);
      }),
    );
    addTearDown(api.close);
    await Future.wait([for (var i = 0; i < 12; i++) api.get('resource/$i')]);
    expect(maximum, 3);
  });
  test('details are cached and failures distinguish 500 from empty', () async {
    var calls = 0;
    final repository = RemoteBangumiRepository(
      apiClient: ApiClient(
        client: MockClient((request) async {
          calls++;
          if (request.url.path == '/p1/subjects/1') {
            return jsonResponse({'id': 1, 'type': 2});
          }
          if (request.url.path.endsWith('/comments')) {
            return jsonResponse({'message': '加载失败'}, 500);
          }
          return jsonResponse({'data': []});
        }),
      ),
    );
    addTearDown(repository.close);
    final first = await repository.fetchSubjectDetails(1);
    final count = calls;
    await repository.fetchSubjectDetails(1);
    // Only successful GETs are cached; failed comments are retried on revisit.
    expect(calls, count + 1);
    expect(first.sectionErrors.keys, ['comments']);
    expect(first.episodes, isEmpty);
  });
  test('successful details revisit sends no additional requests', () async {
    var calls = 0;
    final repository = RemoteBangumiRepository(
      apiClient: ApiClient(
        client: MockClient((request) async {
          calls++;
          return jsonResponse(
            request.url.path == '/p1/subjects/1'
                ? {'id': 1, 'type': 2}
                : {'data': []},
          );
        }),
      ),
    );
    addTearDown(repository.close);
    await repository.fetchSubjectDetails(1);
    final firstCount = calls;
    await repository.fetchSubjectDetails(1);
    expect(calls, firstCount);
  });
  for (final status in [401, 429]) {
    test('optional section $status cannot masquerade as empty', () async {
      final repository = RemoteBangumiRepository(
        apiClient: ApiClient(
          delay: (_) async {},
          client: MockClient((request) async {
            if (request.url.path == '/p1/subjects/1') {
              return jsonResponse({'id': 1, 'type': 2});
            }
            return request.url.path.endsWith('/comments')
                ? jsonResponse({}, status)
                : jsonResponse({'data': []});
          }),
        ),
      );
      addTearDown(repository.close);
      await expectLater(
        repository.fetchSubjectDetails(1),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'code', status),
        ),
      );
    });
  }
  test(
    'profile, character and staff retain optional failure markers',
    () async {
      final repository = RemoteBangumiRepository(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/comments') ||
                request.url.path.endsWith('/blogs')) {
              return jsonResponse({}, 500);
            }
            if (request.url.path == '/p1/users/tester') {
              return jsonResponse({
                'username': 'tester',
                'stats': {'subject': {}},
              });
            }
            if (request.url.path == '/p1/characters/1' ||
                request.url.path == '/p1/persons/1') {
              return jsonResponse({'id': 1});
            }
            return jsonResponse({'data': []});
          }),
        ),
      );
      addTearDown(repository.close);
      expect(
        (await repository.fetchUserProfile('tester')).sectionErrors.keys,
        contains('blogs'),
      );
      expect(
        (await repository.fetchCharacterDetails(1)).sectionErrors.keys,
        contains('comments'),
      );
      expect(
        (await repository.fetchPersonDetails(1)).sectionErrors.keys,
        contains('comments'),
      );
    },
  );
  test(
    'browse and search keep server pagination metadata and cursors',
    () async {
      final requests = <http.Request>[];
      final repository = RemoteBangumiRepository(
        apiClient: ApiClient(
          client: MockClient((request) async {
            requests.add(request);
            return jsonResponse({
              'data': [
                {'id': 1},
              ],
              'total': 101,
              'limit': 30,
              'offset': 30,
            });
          }),
        ),
      );
      addTearDown(repository.close);
      final browse = await repository.fetchSubjectPage(
        type: 2,
        sort: 'rank',
        page: 2,
      );
      expect(requests.last.url.queryParameters['page'], '2');
      expect(browse.total, 101);
      expect(browse.limit, 30);
      expect(browse.offset, 30);
      expect(browse.hasMore, true);
      final search = await repository.searchSubjectPage('test', offset: 30);
      expect(requests.last.url.queryParameters['offset'], '30');
      expect(search.nextOffset, 31);
      await repository.searchSubjectPage('test', offset: 30);
      expect(requests.length, 2);
    },
  );
  test(
    'collection count uses confirmed state and rejects unsupported withdrawal',
    () async {
      var server = 9;
      var interest = 0;
      final api = _UserApi(
        MockClient((request) async {
          if (request.method == 'PUT') {
            interest = (jsonDecode(request.body) as Map)['type'] as int;
            return jsonResponse({});
          }
          if (request.url.path == '/p1/subjects/1') {
            return jsonResponse({
              'id': 1,
              'interest': interest == 0 ? null : {'type': interest},
            });
          }
          return jsonResponse(
            request.url.path == '/p1/users/tester'
                ? {
                  'username': 'tester',
                  'stats': {
                    'subject': {
                      '2': {'2': server},
                    },
                  },
                }
                : {'data': []},
          );
        }),
      );
      final repository = RemoteBangumiRepository(apiClient: api);
      addTearDown(repository.close);
      Future<void> change(int type, bool was) =>
          repository.updateSubjectCollection(
            1,
            type: type,
            rate: 0,
            comment: '',
            isPrivate: false,
            wasCollected: was,
          );
      expect(repository.effectiveSubjectCollectionCount('tester', 9), 9);
      await change(1, false);
      expect(repository.effectiveSubjectCollectionCount('tester', 9), 10);
      await repository.fetchUserProfile('tester');
      expect(repository.effectiveSubjectCollectionCount('tester', 9), 10);
      server = 10;
      repository.invalidateCache();
      await repository.fetchUserProfile('tester');
      expect(repository.effectiveSubjectCollectionCount('tester', 10), 10);
      await change(2, true);
      expect(repository.effectiveSubjectCollectionCount('tester', 10), 10);
      await expectLater(change(0, true), throwsA(isA<ApiException>()));
      expect(repository.effectiveSubjectCollectionCount('tester', 10), 10);
    },
  );
  test('paged controller deduplicates, advances, stops and resets', () async {
    final cursors = <int>[];
    final controller = PagedController<int>(
      idOf: (i) => i,
      load: (cursor) async {
        cursors.add(cursor);
        return cursor == 0
            ? Paged(items: [1, 2], offset: 0, limit: 2, total: 4)
            : Paged(items: [2, 3], offset: 2, limit: 2, total: 4);
      },
    );
    addTearDown(controller.dispose);
    await controller.reset();
    await controller.loadMore();
    await controller.loadMore();
    expect(controller.items, [1, 2, 3]);
    expect(cursors, [0, 2]);
    expect(controller.hasMore, false);
    await controller.reset();
    expect(cursors.last, 0);
  });
  test(
    'old pages are discarded and failed refresh retains data for retry',
    () async {
      final old = Completer<Paged<int>>();
      var calls = 0;
      final controller = PagedController<int>(
        idOf: (i) => i,
        load: (_) async {
          calls++;
          if (calls == 1) return old.future;
          if (calls == 3) throw const ApiException('offline');
          return Paged(items: [calls], offset: 0, limit: 1, total: 1);
        },
      );
      addTearDown(controller.dispose);
      final oldReset = controller.reset();
      await controller.reset();
      old.complete(Paged(items: [1], offset: 0, limit: 1));
      await oldReset;
      expect(controller.items, [2]);
      await controller.reset(keepItems: true);
      expect(controller.items, [2]);
      expect(controller.error, isNotNull);
      await controller.loadMore();
      expect(controller.items, [4]);
      expect(controller.error, isNull);
    },
  );
  test(
    'image bridge transfers path only, streams content and removes temporary file',
    () async {
      final temp = await Directory.systemTemp.createTemp('bangumi-image-test-');
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/image.part');
      await file.writeAsBytes(List.filled(200000, 42));
      const channel = MethodChannel('com.xiaoyv.bangumi/network');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'downloadImage');
            expect((call.arguments as Map).containsKey('body'), false);
            return {
              'path': file.path,
              'length': 200000,
              'statusCode': 200,
              'headers': {'Content-Type': 'image/jpeg', 'ETag': 'test-image'},
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final response = await AndroidImageFileService().get(
        'https://lain.bgm.tv/test.jpg',
      );
      expect(response.fileExtension, '.jpg');
      expect(response.eTag, 'test-image');
      var count = 0;
      var chunks = 0;
      await for (final chunk in response.content) {
        count += chunk.length;
        chunks++;
      }
      expect(count, 200000);
      expect(chunks, greaterThan(1));
      expect(await file.exists(), false);
    },
  );
  test(
    'Android response headers preserve Retry-After regardless of casing',
    () async {
      const channel = MethodChannel('com.xiaoyv.bangumi/network');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => {
              'body': Uint8List(0),
              'statusCode': 429,
              'headers': {'Retry-After': '2'},
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final client = AndroidBangumiHttpClient();
      addTearDown(client.close);
      final response = await client.get(Uri.parse('https://next.bgm.tv/test'));
      expect(response.headers['retry-after'], '2');
    },
  );
  for (final scenario in [
    ('1.1.4+6', 'v1.1.4+7', false, true),
    ('1.1.4+7', 'v1.1.4+6', false, false),
    ('1.1.4+6', 'v1.2.0-rc1', false, false),
    ('1.1.4+6', 'v1.2.0-rc1', true, true),
    ('1.2.0-rc.2', 'v1.2.0-rc.10', true, true),
    ('1.2.0', 'v1.2.0-rc.10', true, false),
  ]) {
    test(
      'version comparison ${scenario.$1} -> ${scenario.$2} prereleases=${scenario.$3}',
      () async {
        final service = AppUpdateService(
          versionProvider: () async => scenario.$1,
          includePrereleases: scenario.$3,
          client: MockClient(
            (_) async => jsonResponse({
              'tag_name': scenario.$2,
              'html_url':
                  'https://github.com/Androdevell/bangumi-flutter/releases/tag/${scenario.$2}',
            }),
          ),
        );
        expect((await service.check()).updateAvailable, scenario.$4);
      },
    );
  }
  for (final url in [
    'http://github.com/Androdevell/bangumi-flutter/releases/tag/v2.0.0',
    'https://evil.test/releases/v2',
    'https://github.com/other/repo/releases/v2',
    'https://github.com@evil.test/releases/v2',
  ]) {
    test('reject untrusted release URL $url', () async {
      final service = AppUpdateService(
        versionProvider: () async => '1.1.6+8',
        client: MockClient(
          (_) async => jsonResponse({'tag_name': 'v2.0.0', 'html_url': url}),
        ),
      );
      final result = await service.check();
      expect(result.releaseUrl, isNull);
      expect(await service.openRelease(result), false);
    });
  }
  test('GitHub rate limit is an explicit update error', () async {
    final service = AppUpdateService(
      versionProvider: () async => '1.1.6+8',
      client: MockClient((_) async => jsonResponse({}, 403)),
    );
    await expectLater(
      service.check(),
      throwsA(
        isA<AppUpdateException>().having(
          (e) => e.message,
          'message',
          contains('频率限制'),
        ),
      ),
    );
  });
}

class _UserApi extends ApiClient {
  _UserApi(http.Client client) : super(client: client);
  @override
  String get currentUsername => 'tester';
  @override
  bool get isLoggedIn => true;
}
