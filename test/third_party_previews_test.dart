import 'dart:async';
import 'dart:convert';

import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/network/third_party_preview_service.dart';
import 'package:bangumi_flutter/core/settings/app_preferences.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const subject = Subject(
  id: 273,
  title: '千与千寻',
  originalTitle: '千と千尋の神隠し',
  type: 2,
  airDate: '2001-07-20',
);
http.Response jsonResponse(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
final suggestions = [
  {'id': '1291561', 'title': subject.title, 'year': '2001'},
];
final photos = {
  'photos': [
    {
      'id': '1',
      'image': {
        'normal': {'url': 'https://img3.doubanio.com/a.jpg'},
        'large': {
          'url': 'https://img3.doubanio.com/b.jpg',
          'width': 1600,
          'height': 900,
        },
      },
    },
  ],
};

class _Vault implements SecureVault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  for (final status in [301, 302, 307, 308]) {
    test('same subject movie to TV redirect $status loads photos', () async {
      final requests = <http.Request>[];
      final service = ThirdPartyPreviewService(
        enabled: true,
        clientFactory:
            () => MockClient((request) async {
              requests.add(request);
              expect(request.followRedirects, false);
              expect(request.headers.containsKey('authorization'), false);
              expect(request.headers.containsKey('cookie'), false);
              if (request.url.host == 'movie.douban.com') {
                return jsonResponse(suggestions);
              }
              if (request.url.path.contains('/movie/')) {
                return http.Response(
                  '',
                  status,
                  headers: {
                    'location':
                        '/rexxar/api/v2/tv/1291561/photos?start=0&count=24',
                  },
                );
              }
              return jsonResponse(photos);
            }),
      );
      addTearDown(service.dispose);
      expect(
        (await service.fetch(subject)).single.imageUrl,
        'https://img3.doubanio.com/a.jpg',
      );
      expect(requests.length, 3);
      expect(requests.last.url.path, '/rexxar/api/v2/tv/1291561/photos');
    });
  }

  for (final target in [
    'https://sec.douban.com/c?verify=1',
    'https://evil.example/rexxar/api/v2/tv/1291561/photos?start=0&count=24',
    'http://m.douban.com/rexxar/api/v2/tv/1291561/photos?start=0&count=24',
    'https://user@m.douban.com/rexxar/api/v2/tv/1291561/photos?start=0&count=24',
    'https://m.douban.com:444/rexxar/api/v2/tv/1291561/photos?start=0&count=24',
    '/rexxar/api/v2/tv/999/photos?start=0&count=24',
    '/rexxar/api/v2/tv/1291561/photos?start=0&count=24&apikey=foreign',
    '/rexxar/api/v2/tv/1291561/photos?start=0&count=24#verify',
    '/rexxar/api/v2/movie/1291561/photos?start=0&count=24',
    '/accounts/login',
  ]) {
    test('noncanonical photo redirect is rejected: $target', () async {
      var requests = 0;
      final service = ThirdPartyPreviewService(
        enabled: true,
        clientFactory:
            () => MockClient((request) async {
              requests++;
              return request.url.host == 'movie.douban.com'
                  ? jsonResponse(suggestions)
                  : http.Response('', 301, headers: {'location': target});
            }),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.fetch(subject),
        throwsA(isA<PreviewException>()),
      );
      expect(requests, 2);
    });
  }

  test('movie/TV redirect loop stops after one redirect', () async {
    var requests = 0;
    final service = ThirdPartyPreviewService(
      enabled: true,
      clientFactory:
          () => MockClient((request) async {
            requests++;
            if (request.url.host == 'movie.douban.com') {
              return jsonResponse(suggestions);
            }
            final kind = request.url.path.contains('/movie/') ? 'tv' : 'movie';
            return http.Response(
              '',
              301,
              headers: {
                'location':
                    '/rexxar/api/v2/$kind/1291561/photos?start=0&count=24',
              },
            );
          }),
    );
    addTearDown(service.dispose);
    await expectLater(service.fetch(subject), throwsA(isA<PreviewException>()));
    expect(requests, 3);
  });

  test(
    'revoking permission during redirect never requests TV photos',
    () async {
      final redirect = Completer<http.Response>();
      final photoRequested = Completer<void>();
      var requests = 0;
      final service = ThirdPartyPreviewService(
        enabled: true,
        clientFactory:
            () => MockClient((request) async {
              requests++;
              if (request.url.host == 'movie.douban.com') {
                return jsonResponse(suggestions);
              }
              photoRequested.complete();
              return redirect.future;
            }),
      );
      addTearDown(service.dispose);
      final pending = service.fetch(subject);
      await photoRequested.future;
      await service.setEnabled(false);
      redirect.complete(
        http.Response(
          '',
          301,
          headers: {
            'location': '/rexxar/api/v2/tv/1291561/photos?start=0&count=24',
          },
        ),
      );
      expect(await pending, isEmpty);
      expect(requests, 2);
    },
  );

  test(
    'new and upgraded installations default off, preference survives reload',
    () async {
      final preferences = AppPreferences(_Vault());
      expect((await preferences.load()).thirdPartyPreviews, false);
      await preferences.setThirdPartyPreviews(true);
      expect((await preferences.load()).thirdPartyPreviews, true);
      await preferences.setThirdPartyPreviews(false);
      expect((await preferences.load()).thirdPartyPreviews, false);
    },
  );

  test('disabled service never creates a transport or sends a title', () async {
    final service = ThirdPartyPreviewService(
      clientFactory: () => throw StateError('must not create'),
    );
    addTearDown(service.dispose);
    expect(await service.fetch(subject), isEmpty);
  });

  test(
    'opt-in still never fetches previews while loading subject details',
    () async {
      final service = ThirdPartyPreviewService(
        enabled: true,
        clientFactory: () => throw StateError('must not create'),
      );
      final repo = RemoteBangumiRepository(
        previewService: service,
        apiClient: ApiClient(
          client: MockClient((r) async {
            expect(r.url.host, 'next.bgm.tv');
            if (r.url.path == '/p1/subjects/273') {
              return jsonResponse({
                'id': 273,
                'type': 2,
                'name_cn': subject.title,
              });
            }
            return jsonResponse({'data': []});
          }),
        ),
      );
      addTearDown(repo.close);
      expect((await repo.fetchSubjectDetails(273)).previews, isEmpty);
    },
  );

  test(
    'public requests omit Bangumi credentials and reject redirects',
    () async {
      final requests = <http.Request>[];
      final service = ThirdPartyPreviewService(
        enabled: true,
        clientFactory:
            () => MockClient((r) async {
              requests.add(r);
              expect(
                r.headers.keys.map((key) => key.toLowerCase()),
                isNot(contains('authorization')),
              );
              expect(
                r.headers.keys.map((key) => key.toLowerCase()),
                isNot(contains('cookie')),
              );
              expect(r.followRedirects, false);
              expect(r.url.queryParameters.containsKey('apikey'), false);
              expect(r.url.queryParameters.containsKey('_sig'), false);
              return r.url.host == 'movie.douban.com'
                  ? jsonResponse(suggestions)
                  : jsonResponse(photos);
            }),
      );
      addTearDown(service.dispose);
      final result = await service.fetch(subject);
      expect(result.single.imageUrl, 'https://img3.doubanio.com/a.jpg');
      expect(result.single.largeImageUrl, 'https://img3.doubanio.com/b.jpg');
      expect(requests.map((r) => r.url.host), [
        'movie.douban.com',
        'm.douban.com',
      ]);
      expect(requests.last.url.path, '/rexxar/api/v2/movie/1291561/photos');
    },
  );

  test('failed enable persistence does not grant permission', () async {
    final service = ThirdPartyPreviewService(
      persist: (_) async => throw StateError('storage'),
      clientFactory: () => throw StateError('must not create'),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.setEnabled(true),
      throwsA(isA<PreviewException>()),
    );
    expect(service.enabled, false);
    expect(await service.fetch(subject), isEmpty);
  });

  test('disable revokes permission even when saving fails', () async {
    final service = ThirdPartyPreviewService(
      enabled: true,
      persist: (_) async => throw StateError('storage'),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.setEnabled(false),
      throwsA(isA<PreviewException>()),
    );
    expect(service.enabled, false);
    expect(await service.fetch(subject), isEmpty);
  });

  test(
    'revoke during pending search stops photo request and discards old result',
    () async {
      final search = Completer<http.Response>();
      var calls = 0;
      final service = ThirdPartyPreviewService(
        enabled: true,
        clientFactory:
            () => MockClient((r) {
              calls++;
              return search.future;
            }),
      );
      addTearDown(service.dispose);
      final result = service.fetch(subject);
      await Future<void>.delayed(Duration.zero);
      await service.setEnabled(false);
      search.complete(jsonResponse(suggestions));
      expect(await result, isEmpty);
      expect(calls, 1);
    },
  );

  test(
    'enable/disable persistence is serialized and last choice wins',
    () async {
      final gate = Completer<void>();
      final saved = <bool>[];
      final service = ThirdPartyPreviewService(
        persist: (value) async {
          if (value) await gate.future;
          saved.add(value);
        },
      );
      addTearDown(service.dispose);
      final enable = service.setEnabled(true);
      final disable = service.setEnabled(false);
      gate.complete();
      await Future.wait([enable, disable]);
      expect(saved, [true, false]);
      expect(service.enabled, false);
    },
  );

  test('cache coalesces requests, refresh and revoke invalidate', () async {
    var calls = 0;
    final service = ThirdPartyPreviewService(
      enabled: true,
      clientFactory:
          () => MockClient((r) async {
            calls++;
            return r.url.host == 'movie.douban.com'
                ? jsonResponse(suggestions)
                : jsonResponse(photos);
          }),
    );
    addTearDown(service.dispose);
    await Future.wait([service.fetch(subject), service.fetch(subject)]);
    expect(calls, 2);
    await service.fetch(subject, refresh: true);
    expect(calls, 4);
    await service.setEnabled(false);
    await service.setEnabled(true);
    await service.fetch(subject);
    expect(calls, 6);
  });

  for (final status in [302, 403, 429, 500]) {
    test(
      'HTTP $status is a typed failure, never interpreted as empty photos',
      () async {
        final service = ThirdPartyPreviewService(
          enabled: true,
          clientFactory:
              () => MockClient(
                (r) async => http.Response('private title', status),
              ),
        );
        addTearDown(service.dispose);
        await expectLater(
          service.fetch(subject),
          throwsA(
            isA<PreviewException>().having(
              (e) => e.failure,
              'kind',
              PreviewFailure.unavailable,
            ),
          ),
        );
      },
    );
  }

  test('malformed JSON is distinct from network failure', () async {
    final service = ThirdPartyPreviewService(
      enabled: true,
      clientFactory:
          () => MockClient(
            (r) async => http.Response('<html>verify</html>', 200),
          ),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.fetch(subject),
      throwsA(
        isA<PreviewException>().having(
          (e) => e.failure,
          'kind',
          PreviewFailure.invalidResponse,
        ),
      ),
    );
  });

  test(
    'wrong-year match does not query photos; books never query provider',
    () async {
      var calls = 0;
      final service = ThirdPartyPreviewService(
        enabled: true,
        clientFactory:
            () => MockClient((r) async {
              calls++;
              return jsonResponse([
                {'id': '9', 'title': subject.title, 'year': '2030'},
              ]);
            }),
      );
      addTearDown(service.dispose);
      expect(await service.fetch(subject), isEmpty);
      expect(calls, 2);
      expect(
        await service.fetch(const Subject(id: 5, title: 'book', type: 1)),
        isEmpty,
      );
      expect(calls, 2);
    },
  );

  test(
    'image parser rejects external hosts and accepts HTTPS Douban images only',
    () async {
      final service = ThirdPartyPreviewService(
        enabled: true,
        clientFactory:
            () => MockClient((r) async {
              if (r.url.host == 'movie.douban.com') {
                return jsonResponse(suggestions);
              }
              return jsonResponse({
                'photos': [
                  {
                    'image': {
                      'normal': {'url': 'http://img3.doubanio.com/a.jpg'},
                    },
                  },
                  {
                    'image': {
                      'normal': {'url': 'https://evil.test/a.jpg'},
                    },
                  },
                  {
                    'image': {
                      'normal': {'url': 'https://doubanio.com.evil.test/a.jpg'},
                    },
                  },
                  ...photos['photos'] as List,
                ],
              });
            }),
      );
      addTearDown(service.dispose);
      expect(await service.fetch(subject), hasLength(1));
    },
  );
}
