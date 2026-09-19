import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/community_models.dart';
import '../core/network/api_client.dart';
import '../core/network/platform_http_client.dart';
import '../core/subject_detail_models.dart';

abstract interface class BangumiRepository {
  bool get isLoggedIn;
  String get currentUsername;
  Listenable get collectionChanges;
  int get pendingSubjectCollectionDelta;
  Future<Map<String, List<Subject>>> fetchCalendar();
  Future<List<Subject>> fetchTrending({int type = 2, int limit = 20});
  Future<List<Subject>> fetchSubjects({
    required int type,
    required String sort,
    int page = 1,
  });
  Future<List<Subject>> searchSubjects(String keyword, {int? type});
  Future<Subject> fetchSubject(int id);
  Future<SubjectDetailData> fetchSubjectDetails(int id);
  Future<List<TimelineEntry>> fetchTimeline({
    String mode = 'all',
    int? category,
  });
  Future<List<Topic>> fetchTopics({String type = 'all'});
  Future<TopicDetailData> fetchTopicDetails(Topic topic);
  Future<UserProfileData> fetchUserProfile(String username);
  Future<CharacterDetailData> fetchCharacterDetails(int id);
  Future<PersonDetailData> fetchPersonDetails(int id);
  Future<List<CommunityReply>> fetchEpisodeComments(int episodeId);
  Future<void> createEpisodeComment(int episodeId, String content);
  Future<List<CommunityReply>> fetchPersonComments(int personId);
  Future<void> updateSubjectCollection(
    int subjectId, {
    required int type,
    required int rate,
    required String comment,
    required bool isPrivate,
    bool wasCollected = true,
  });
  Future<void> updateEpisodeProgress(
    int episodeId,
    int type, {
    bool batch = false,
  });
  Future<void> toggleCharacterCollection(int characterId, bool collected);
  Future<void> toggleFriend(String username, bool isFriend);
  Future<void> setEpisodeCommentReaction(int commentId, String? value);
  Future<void> setSubjectCommentReaction(int commentId, String? value);
  Future<void> setTopicPostReaction(
    String topicType,
    int postId,
    String? value,
  );
  Future<void> setTimelineReaction(int timelineId, String? value);
  void close();
}

class RemoteBangumiRepository implements BangumiRepository {
  RemoteBangumiRepository({ApiClient? apiClient, http.Client? externalClient})
    : _api = apiClient ?? ApiClient(),
      _externalClient = externalClient ?? createPlatformHttpClient();

  final ApiClient _api;
  final http.Client _externalClient;
  final ValueNotifier<int> _collectionChanges = ValueNotifier(0);
  final Map<String, int> _pendingSubjectCollectionDeltas = {};

  @override
  bool get isLoggedIn => _api.isLoggedIn;

  @override
  String get currentUsername => _api.currentUsername;

  @override
  Listenable get collectionChanges => _collectionChanges;

  @override
  int get pendingSubjectCollectionDelta =>
      _pendingSubjectCollectionDeltas[currentUsername] ?? 0;

  @override
  Future<Map<String, List<Subject>>> fetchCalendar() async {
    final json = await _api.get('p1/calendar');
    if (json is! Map) throw const ApiException('每日放送数据格式不正确');
    return json.map((key, value) {
      final items = value is List ? value : const [];
      return MapEntry(
        '$key',
        items.map(_subjectFromWrapper).where((item) => item.id > 0).toList(),
      );
    });
  }

  @override
  Future<List<Subject>> fetchTrending({int type = 2, int limit = 20}) async {
    final json = await _api.get(
      'p1/trending/subjects',
      query: {'type': '$type', 'offset': '0', 'limit': '$limit'},
    );
    return _subjectPage(json);
  }

  @override
  Future<List<Subject>> fetchSubjects({
    required int type,
    required String sort,
    int page = 1,
  }) async {
    final json = await _api.get(
      'p1/subjects',
      query: {'type': '$type', 'sort': sort, 'page': '$page'},
    );
    return _subjectPage(json);
  }

  @override
  Future<List<Subject>> searchSubjects(String keyword, {int? type}) async {
    final filter = <String, dynamic>{'nsfw': true};
    if (type != null && type > 0) filter['type'] = [type];
    final json = await _api.post(
      'p1/search/subjects',
      query: {'offset': '0', 'limit': '30'},
      body: {'keyword': keyword, 'filter': filter, 'sort': 'match'},
    );
    return _subjectPage(json);
  }

  @override
  Future<Subject> fetchSubject(int id) async {
    return Subject.fromJson(await _fetchSubjectJson(id));
  }

  @override
  Future<SubjectDetailData> fetchSubjectDetails(int id) async {
    final subjectJson = await _fetchSubjectJson(id);
    final subject = Subject.fromJson(subjectJson);
    final results = await Future.wait<List<Object>>([
      _safeItems(
        _fetchItems('p1/subjects/$id/episodes', SubjectEpisode.fromJson, 100),
      ),
      _safeItems(_fetchPreviews(subject)),
      _safeItems(
        _fetchItems('p1/subjects/$id/comments', SubjectComment.fromJson, 40),
      ),
      _safeItems(
        _fetchItems(
          'p1/subjects/$id/characters',
          SubjectCharacter.fromJson,
          100,
        ),
      ),
      _safeItems(
        _fetchItems(
          'p1/subjects/$id/staffs/persons',
          SubjectStaff.fromJson,
          100,
        ),
      ),
      _safeItems(
        _fetchItems('p1/subjects/$id/relations', SubjectRelation.fromJson, 100),
      ),
      _safeItems(
        _fetchItems('p1/subjects/$id/indexes', SubjectIndex.fromJson, 40),
      ),
      _safeItems(
        _fetchItems('p1/subjects/$id/reviews', SubjectReview.fromJson, 20),
      ),
      _safeItems(
        _fetchItems('p1/subjects/$id/topics', SubjectTopic.fromJson, 40),
      ),
    ]);

    return SubjectDetailData.fromSubjectJson(
      json: subjectJson,
      episodes: results[0].cast<SubjectEpisode>(),
      previews: results[1].cast<SubjectPreview>(),
      comments: results[2].cast<SubjectComment>(),
      characters: results[3].cast<SubjectCharacter>(),
      staffs: results[4].cast<SubjectStaff>(),
      relations: results[5].cast<SubjectRelation>(),
      indexes: results[6].cast<SubjectIndex>(),
      reviews: results[7].cast<SubjectReview>(),
      topics: results[8].cast<SubjectTopic>(),
    );
  }

  @override
  Future<List<TimelineEntry>> fetchTimeline({
    String mode = 'all',
    int? category,
  }) async {
    final query = <String, String>{'mode': mode, 'limit': '20'};
    if (category != null) query['cat'] = '$category';
    final json = await _api.get('p1/timeline', query: query);
    if (json is! List) throw const ApiException('时间线数据格式不正确');
    return json
        .whereType<Map>()
        .map((item) => TimelineEntry.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  @override
  Future<List<Topic>> fetchTopics({String type = 'all'}) async {
    final json = await _api.get(
      'p1/rakuen/topics',
      query: {'type': type, 'limit': '60'},
    );
    final data = json is Map ? json['data'] ?? json['result'] : json;
    if (data is! List) throw const ApiException('超展开数据格式不正确');
    return data
        .whereType<Map>()
        .map((item) => Topic.fromJson(Map<String, dynamic>.from(item)))
        .where((topic) => topic.title.isNotEmpty)
        .toList();
  }

  @override
  Future<TopicDetailData> fetchTopicDetails(Topic topic) async {
    if (topic.type != 'group' && topic.type != 'subject') {
      throw const ApiException('该类型没有讨论详情接口');
    }
    final owner = topic.type == 'group' ? 'groups' : 'subjects';
    final json = await _api.get('p1/$owner/-/topics/${topic.id}');
    if (json is! Map) throw const ApiException('讨论详情数据格式不正确');
    return TopicDetailData.fromJson(
      Map<String, dynamic>.from(json),
      type: topic.type,
    );
  }

  @override
  Future<UserProfileData> fetchUserProfile(String username) async {
    final encoded = Uri.encodeComponent(username);
    final results = await Future.wait<dynamic>([
      _api.get('p1/users/$encoded'),
      _safeJson(
        _api.get('p1/users/$encoded/timeline', query: {'limit': '20'}),
        const [],
      ),
      _safeJson(
        _api.get(
          'p1/users/$encoded/collections/subjects',
          query: {'limit': '40'},
        ),
        const {},
      ),
      _safeJson(
        _api.get(
          'p1/users/$encoded/collections/characters',
          query: {'limit': '40'},
        ),
        const {},
      ),
      _safeJson(
        _api.get(
          'p1/users/$encoded/collections/persons',
          query: {'limit': '40'},
        ),
        const {},
      ),
      _safeJson(
        _api.get('p1/users/$encoded/blogs', query: {'limit': '30'}),
        const {},
      ),
      _safeJson(
        _api.get('p1/users/$encoded/indexes', query: {'limit': '30'}),
        const {},
      ),
      _safeJson(
        _api.get('p1/users/$encoded/friends', query: {'limit': '50'}),
        const {},
      ),
    ]);
    if (results.first is! Map) throw const ApiException('用户资料格式不正确');
    return UserProfileData(
      user: CommunityUser.fromJson(
        Map<String, dynamic>.from(results[0] as Map),
      ),
      timeline:
          _items(results[1])
              .map(
                (item) => TimelineEntry.fromJson({
                  ...item,
                  if (item['user'] == null) 'user': results[0],
                }),
              )
              .toList(),
      collections: _items(results[2]).map(UserContentItem.fromSubject).toList(),
      characters: _items(results[3]).map(UserContentItem.fromMono).toList(),
      persons: _items(results[4]).map(UserContentItem.fromMono).toList(),
      blogs: _items(results[5]).map(UserContentItem.fromBlog).toList(),
      indexes: _items(results[6]).map(UserContentItem.fromIndex).toList(),
      friends: _items(results[7]).map(CommunityUser.fromJson).toList(),
    );
  }

  @override
  Future<CharacterDetailData> fetchCharacterDetails(int id) async {
    final results = await Future.wait<dynamic>([
      _api.get('p1/characters/$id'),
      _safeJson(
        _api.get('p1/characters/$id/casts', query: {'limit': '100'}),
        const {},
      ),
      _safeJson(
        _api.get('p1/characters/$id/collects', query: {'limit': '50'}),
        const {},
      ),
      _safeJson(_api.get('p1/characters/$id/comments'), const []),
      _safeJson(
        _api.get('p1/characters/$id/indexes', query: {'limit': '40'}),
        const {},
      ),
    ]);
    if (results.first is! Map) throw const ApiException('角色资料格式不正确');
    return CharacterDetailData(
      character: CharacterEntry.fromJson(
        Map<String, dynamic>.from(results[0] as Map),
      ),
      works: _items(results[1]).map(CharacterWork.fromJson).toList(),
      collectors:
          _items(
            results[2],
          ).map((item) => CommunityUser.fromJson(_map(item['user']))).toList(),
      comments: _items(results[3]).map(CommunityReply.fromJson).toList(),
      indexes: _items(results[4]).map(UserContentItem.fromIndex).toList(),
    );
  }

  @override
  Future<List<CommunityReply>> fetchEpisodeComments(int episodeId) async {
    final json = await _api.get('p1/episodes/$episodeId/comments');
    return _items(json)
        .map(CommunityReply.fromJson)
        .where((item) => item.content.isNotEmpty)
        .toList();
  }

  @override
  Future<void> createEpisodeComment(int episodeId, String content) async {
    final value = content.trim();
    if (value.isEmpty) throw const ApiException('评论内容不能为空');
    final formHash = _api.formHash;
    if (!_api.isLoggedIn || formHash.isEmpty) {
      throw const ApiException('请先登录后再发表评论');
    }
    final json = await _api.postWebForm(
      'subject/ep/$episodeId/new_reply?ajax=1',
      referer: 'https://bgm.tv/ep/$episodeId',
      fields: {
        'lastview': '',
        'formhash': formHash,
        'content': value,
        'submit': 'submit',
      },
    );
    if (json is Map && json['status'] == 'error') {
      throw ApiException('${json['msg'] ?? json['message'] ?? '评论发布失败'}');
    }
  }

  @override
  Future<List<CommunityReply>> fetchPersonComments(int personId) async {
    final json = await _api.get('p1/persons/$personId/comments');
    return _items(json)
        .map(CommunityReply.fromJson)
        .where((item) => item.content.isNotEmpty)
        .toList();
  }

  @override
  Future<void> updateSubjectCollection(
    int subjectId, {
    required int type,
    required int rate,
    required String comment,
    required bool isPrivate,
    bool wasCollected = true,
  }) async {
    await _api.put(
      'p1/collections/subjects/$subjectId',
      body: {
        'type': type,
        'rate': rate,
        'comment': comment,
        'private': isPrivate,
        'tags': <String>[],
      },
    );
    if (!wasCollected && type > 0 && currentUsername.isNotEmpty) {
      _pendingSubjectCollectionDeltas.update(
        currentUsername,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    _collectionChanges.value++;
  }

  @override
  Future<void> updateEpisodeProgress(
    int episodeId,
    int type, {
    bool batch = false,
  }) => _api.patch(
    'p1/collections/episodes/$episodeId',
    body: {'type': type, 'batch': batch},
  );

  @override
  Future<void> toggleCharacterCollection(
    int characterId,
    bool collected,
  ) async {
    if (collected) {
      await _api.delete(
        'p1/collections/characters/$characterId',
        body: const {},
      );
    } else {
      await _api.put('p1/collections/characters/$characterId', body: const {});
    }
    _collectionChanges.value++;
  }

  @override
  Future<PersonDetailData> fetchPersonDetails(int id) async {
    final results = await Future.wait<dynamic>([
      _api.get('p1/persons/$id'),
      _safeJson(_api.get('p1/persons/$id/comments'), const []),
    ]);
    if (results.first is! Map) throw const ApiException('制作人员资料格式不正确');
    return PersonDetailData(
      person: PersonEntry.fromJson(
        Map<String, dynamic>.from(results.first as Map),
      ),
      comments: _items(results[1]).map(CommunityReply.fromJson).toList(),
    );
  }

  @override
  Future<void> toggleFriend(String username, bool isFriend) {
    final encoded = Uri.encodeComponent(username);
    return isFriend
        ? _api.delete('p1/friends/$encoded')
        : _api.put('p1/friends/$encoded');
  }

  @override
  Future<void> setEpisodeCommentReaction(int commentId, String? value) =>
      value == null
          ? _api.delete('p1/episodes/-/comments/$commentId/like')
          : _api.put(
            'p1/episodes/-/comments/$commentId/like',
            body: {'value': int.parse(value)},
          );

  @override
  Future<void> setSubjectCommentReaction(int commentId, String? value) =>
      value == null
          ? _api.delete('p1/subjects/-/collects/$commentId/like')
          : _api.put(
            'p1/subjects/-/collects/$commentId/like',
            body: {'value': int.parse(value)},
          );

  @override
  Future<void> setTopicPostReaction(
    String topicType,
    int postId,
    String? value,
  ) {
    if (topicType != 'group' && topicType != 'subject') {
      throw const ApiException('该类型不支持贴贴');
    }
    final owner = topicType == 'group' ? 'groups' : 'subjects';
    final path = 'p1/$owner/-/posts/$postId/like';
    return value == null
        ? _api.delete(path)
        : _api.put(path, body: {'value': int.parse(value)});
  }

  @override
  Future<void> setTimelineReaction(int timelineId, String? value) =>
      value == null
          ? _api.delete('p1/timeline/$timelineId/like')
          : _api.put(
            'p1/timeline/$timelineId/like',
            body: {'value': int.parse(value)},
          );

  List<Subject> _subjectPage(dynamic json) {
    final data = json is Map ? json['data'] ?? json['result'] : json;
    if (data is! List) throw const ApiException('条目列表数据格式不正确');
    return data.map(_subjectFromWrapper).where((item) => item.id > 0).toList();
  }

  Subject _subjectFromWrapper(dynamic value) {
    if (value is! Map) return const Subject(id: 0, title: '');
    final map = Map<String, dynamic>.from(value);
    final nested = map['subject'];
    if (nested is Map) {
      return Subject.fromJson(Map<String, dynamic>.from(nested));
    }
    return Subject.fromJson(map);
  }

  Future<Map<String, dynamic>> _fetchSubjectJson(int id) async {
    final json = await _api.get('p1/subjects/$id');
    if (json is! Map) throw const ApiException('条目数据格式不正确');
    return Map<String, dynamic>.from(json);
  }

  Future<List<T>> _fetchItems<T>(
    String path,
    T Function(Map<String, dynamic>) parser,
    int limit,
  ) async {
    final json = await _api.get(path, query: {'limit': '$limit'});
    final data = json is Map ? json['data'] ?? json['result'] : json;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => parser(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<Object>> _safeItems<T>(Future<List<T>> request) async {
    try {
      return (await request).cast<Object>();
    } on Object {
      return const [];
    }
  }

  Future<List<SubjectPreview>> _fetchPreviews(Subject subject) async {
    if (subject.title.isEmpty) return const [];
    final suggestionUri = _signedDoubanUri(
      Uri.https('frodo.douban.com', '/api/v2/search/suggestion', {
        'q': subject.title,
        'apikey': _doubanApiKey,
      }),
    );
    final suggestionResponse = await _externalClient
        .get(suggestionUri, headers: {'User-Agent': _doubanUserAgent})
        .timeout(const Duration(seconds: 12));
    if (suggestionResponse.statusCode != 200) return const [];
    final suggestion = jsonDecode(utf8.decode(suggestionResponse.bodyBytes));
    if (suggestion is! Map || suggestion['cards'] is! List) return const [];
    final cards = (suggestion['cards'] as List).whereType<Map>();
    Map<dynamic, dynamic>? selected;
    for (final card in cards) {
      if ('${card['target_type']}' != 'explore') {
        selected = card;
        break;
      }
    }
    final targetId = selected?['target_id']?.toString() ?? '';
    final targetType = selected?['target_type']?.toString() ?? 'tv';
    if (targetId.isEmpty) return const [];

    final photoUri = _signedDoubanUri(
      Uri.https('frodo.douban.com', '/api/v2/$targetType/$targetId/photos', {
        'start': '0',
        'count': '60',
        'apikey': _doubanApiKey,
      }),
    );
    final photoResponse = await _externalClient
        .get(photoUri, headers: {'User-Agent': _doubanUserAgent})
        .timeout(const Duration(seconds: 12));
    if (photoResponse.statusCode != 200) return const [];
    final payload = jsonDecode(utf8.decode(photoResponse.bodyBytes));
    if (payload is! Map || payload['photos'] is! List) return const [];
    return (payload['photos'] as List)
        .whereType<Map>()
        .map((photo) {
          final image = _asMap(photo['image']);
          final normal = _asMap(image['normal']);
          final large = _asMap(image['large']);
          return SubjectPreview(
            id: '${photo['id'] ?? ''}',
            imageUrl: _secureImageUrl('${normal['url'] ?? large['url'] ?? ''}'),
            largeImageUrl: _secureImageUrl(
              '${large['url'] ?? normal['url'] ?? ''}',
            ),
            width: (large['width'] as num?)?.toInt() ?? 0,
            height: (large['height'] as num?)?.toInt() ?? 0,
          );
        })
        .where((photo) => photo.imageUrl.isNotEmpty)
        .toList();
  }

  Uri _signedDoubanUri(Uri uri) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final source = 'GET&${Uri.encodeComponent(uri.path)}&$timestamp';
    final signature = base64Encode(
      Hmac(
        sha1,
        utf8.encode(_doubanSignKey),
      ).convert(utf8.encode(source)).bytes,
    );
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        '_sig': signature,
        '_ts': '$timestamp',
      },
    );
  }

  String _secureImageUrl(String value) =>
      value.startsWith('//')
          ? 'https:$value'
          : value.replaceFirst(RegExp(r'^http://'), 'https://');

  Map<String, dynamic> _asMap(dynamic value) =>
      value is Map
          ? value.map((key, item) => MapEntry('$key', item))
          : const {};

  Future<dynamic> _safeJson(Future<dynamic> request, dynamic fallback) async {
    try {
      return await request;
    } on Object {
      return fallback;
    }
  }

  List<Map<String, dynamic>> _items(dynamic json) {
    final data = json is Map ? json['data'] ?? json['result'] : json;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  @override
  void close() {
    _collectionChanges.dispose();
    _api.close();
    _externalClient.close();
  }

  static const _doubanApiKey = '0dad551ec0f84ed02907ff5c42e8ec70';
  static const _doubanSignKey = 'bf7dddc7c9cfe6f7';
  static const _doubanUserAgent =
      'api-client/1 com.douban.frodo/7.65.0(277) Android/33 '
      'product/coral vendor/Google model/Pixel 4 XL brand/google rom/android '
      'network/wifi platform/mobile nd/1';
}
