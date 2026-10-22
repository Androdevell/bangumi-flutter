import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/core/navigation/bangumi_link.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/network/public_address.dart';
import 'package:bangumi_flutter/core/network/windows_direct_client.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/data/repositories/remote_episode_progress_repository.dart';
import 'package:bangumi_flutter/domain/repositories/tag_repository.dart';
import 'package:bangumi_flutter/widgets/image_viewer_page.dart';
import 'community_extensions_test.dart' show authenticated;
import 'package:bangumi_flutter/app/state/session_scope.dart';
import 'package:bangumi_flutter/core/subject_detail_models.dart';

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
  test(
    'poster target decoding does not ask non-image cache for disk resize',
    () {
      final source = File('lib/widgets/subject_card.dart').readAsStringSync();
      expect(source, contains('memCacheWidth: cacheWidth'));
      expect(source, isNot(contains('maxWidthDiskCache:')));
    },
  );
  test('known Bangumi routes and mixed shared text', () {
    for (final host in BangumiLinkParser.hosts) {
      expect(
        BangumiLinkParser.parse('作品 https://$host/subject/42。')?.key,
        '42',
      );
      expect(
        BangumiLinkParser.parse('http://$host/user/abc_123')?.kind,
        'user',
      );
      expect(
        BangumiLinkParser.parse('https://$host/group/topic/4')?.kind,
        'groupTopic',
      );
      expect(BangumiLinkParser.parse('https://$host/ep/1737853')?.kind, 'ep');
    }
  });
  test('reject spoofed hosts, credentials, invalid ids and ports', () {
    for (final value in [
      'https://bgm.tv.evil.test/subject/4',
      'https://evil.test@bgm.tv/subject/4',
      'https://bgm.tv:444/subject/4',
      'https://bgm.tv/subject/0',
      'https://bgm.tv/subject/-1',
      'https://bgm.tv/user/a%2Fb',
      'https://bgm.tv/subject/99999999999999999999999999',
      'https://bgm.tv/subject/4/extra',
      'javascript:alert(1)',
      'x' * 8193,
    ]) {
      expect(BangumiLinkParser.parse(value), isNull, reason: value);
    }
  });
  test('zoom keeps click anchor; fit and resize reset exactly', () {
    final zoom = ImageZoomController();
    addTearDown(zoom.dispose);
    zoom.configure(const Size(800, 600), image: const Size(800, 600));
    const anchor = Offset(300, 250);
    final scene = zoom.toScene(anchor);
    zoom.zoomAt(2.5, anchor);
    expect(zoom.toScene(anchor), scene);
    zoom.zoomAt(100, anchor);
    expect(zoom.scale, 8);
    zoom.reset();
    expect(zoom.value, Matrix4.identity());
    zoom.zoomAt(2, anchor);
    zoom.configure(const Size(400, 600));
    expect(zoom.value, Matrix4.identity());
  });
  test('portrait and landscape pan remains inside actual fitted content', () {
    for (final image in [const Size(100, 1000), const Size(2000, 100)]) {
      final zoom =
          ImageZoomController()..configure(const Size(800, 600), image: image);
      zoom.zoomAt(2, const Offset(400, 300));
      zoom.value =
          Matrix4.identity()
            ..translate(100000.0, -100000.0)
            ..scale(2.0);
      zoom.clampBounds();
      final t = zoom.value.getTranslation();
      expect(t.x.abs(), lessThanOrEqualTo(800));
      expect(t.y.abs(), lessThanOrEqualTo(600));
      zoom.dispose();
    }
  });
  test('tag query uses exact tags field and URL-safe encoding', () async {
    final api = ApiClient(
      client: MockClient((request) async {
        expect(request.url.path, '/p1/subjects');
        expect(request.url.queryParameters, {
          'type': '1',
          'sort': 'rank',
          'page': '2',
          'tags': '日文 + # /',
        });
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 4, 'name': 'Book'},
            ],
            'total': 21,
          }),
          200,
        );
      }),
    );
    final repo = RemoteBangumiRepository(apiClient: api);
    final page = await repo.tagPage(const ComposeTagQuery(1, '日文 + # /'), 2);
    expect(page.items.single.id, 4);
    expect(page.hasMore, isFalse);
    repo.close();
  });
  test(
    'uncollected subject sends zero episode writes even through repository',
    () async {
      var writes = 0;
      final (api, auth) = await authenticated(
        MockClient((request) async {
          if (request.method != 'GET') writes++;
          return http.Response('{"interest":null}', 200);
        }),
      );
      final repo = RemoteEpisodeProgressRepository(api, onChanged: () {});
      await expectLater(
        repo.save(8, 3, 2, session: api.sessionScope),
        throwsA(isA<ApiException>()),
      );
      expect(writes, 0);
      api.close();
      auth.dispose();
    },
  );
  test(
    'DNS destinations exclude private and IPv4-mapped loopback addresses',
    () {
      for (final value in [
        '127.0.0.1',
        '10.1.1.1',
        '192.168.0.1',
        '169.254.1.1',
        '::1',
        '::ffff:127.0.0.1',
        'fc00::1',
      ]) {
        expect(isPublicAddress(InternetAddress(value)), isFalse);
      }
      expect(isPublicAddress(InternetAddress('104.26.8.23')), isTrue);
    },
  );
  test('TLS fragmentation preserves payload across chunk boundaries', () async {
    final name = ascii.encode('next.bgm.tv');
    final ext = [
      0,
      0,
      0,
      name.length + 5,
      0,
      name.length + 3,
      0,
      0,
      name.length,
      ...name,
    ];
    final hello = [
      1,
      0,
      0,
      0,
      3,
      3,
      ...List.filled(32, 0),
      0,
      0,
      2,
      0x13,
      1,
      1,
      0,
      0,
      ext.length,
      ...ext,
    ];
    final record = [22, 3, 1, hello.length >> 8, hello.length & 255, ...hello];
    final split = clientHelloSniSplit(record);
    expect(split, isNotNull);
    final parts =
        await fragmentClientHello(
          Stream.fromIterable([
            record.sublist(0, 3),
            record.sublist(3),
            [23, 3, 3, 0, 0],
          ]),
        ).toList();
    final payload = <int>[];
    for (final part in parts.take(4)) {
      expect(part[0], 22);
      expect((part[3] << 8) + part[4], part.length - 5);
      payload.addAll(part.skip(5));
    }
    expect(payload, hello);
    expect(parts.last, [23, 3, 3, 0, 0]);
    expect(clientHelloSniSplit([22, 3, 3, 0, 0]), isNull);
  });
}
