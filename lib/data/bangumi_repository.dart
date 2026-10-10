import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../core/paged.dart';
import '../core/community_models.dart';
import '../core/network/api_client.dart';
import '../core/network/third_party_preview_service.dart';
import '../core/subject_detail_models.dart';

abstract interface class BangumiRepository {
  bool get isLoggedIn;
  String get currentUsername;
  Listenable get collectionChanges;
  int effectiveSubjectCollectionCount(String username, int serverCount);
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
  Future<void> createTopicReply(Topic topic, String content);
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

abstract interface class SubjectPagingRepository {
  Future<Paged<Subject>> fetchSubjectPage({
    required int type,
    required String sort,
    int page = 1,
  });
  Future<Paged<Subject>> searchSubjectPage(
    String keyword, {
    int? type,
    int offset = 0,
  });
}

abstract interface class RefreshableRepository {
  void invalidateCache();
}

abstract interface class SubjectPreviewRepository {
  ThirdPartyPreviewService get previewService;
}

ThirdPartyPreviewService? previewServiceFor(BangumiRepository repository) =>
    repository is SubjectPreviewRepository
        ? (repository as SubjectPreviewRepository).previewService
        : null;

void invalidateRepositoryCache(BangumiRepository repository) {
  if (repository is RefreshableRepository) {
    (repository as RefreshableRepository).invalidateCache();
  }
}

Future<Paged<Subject>> subjectPage(
  BangumiRepository repository, {
  required int type,
  required String sort,
  int page = 1,
}) async {
  if (repository is SubjectPagingRepository) {
    return (repository as SubjectPagingRepository).fetchSubjectPage(
      type: type,
      sort: sort,
      page: page,
    );
  }
  return Paged(
    items: await repository.fetchSubjects(type: type, sort: sort, page: page),
    offset: (page - 1) * 20,
    limit: 20,
  );
}

Future<Paged<Subject>> searchPage(
  BangumiRepository repository,
  String keyword, {
  int? type,
  int offset = 0,
}) async {
  if (repository is SubjectPagingRepository) {
    return (repository as SubjectPagingRepository).searchSubjectPage(
      keyword,
      type: type,
      offset: offset,
    );
  }
  if (offset > 0) return Paged(items: const [], offset: offset, limit: 30);
  final items = await repository.searchSubjects(keyword, type: type);
  return Paged(items: items, offset: 0, limit: 30, total: items.length);
}

class RemoteBangumiRepository
    implements
        BangumiRepository,
        SubjectPagingRepository,
        SubjectPreviewRepository,
        RefreshableRepository {
  RemoteBangumiRepository({
    ApiClient? apiClient,
    ThirdPartyPreviewService? previewService,
  }) : _api = apiClient ?? ApiClient(),
       previewService = previewService ?? ThirdPartyPreviewService();

  @override
  final ThirdPartyPreviewService previewService;

  final ApiClient _api;
  final ValueNotifier<int> _collectionChanges = ValueNotifier(0);
  final Map<String, _CollectionCount> _subjectCollectionCounts = {};
  final Map<String, ({DateTime at, Future<Paged<Subject>> request})>
  _searchCache = {};

  @override
  void invalidateCache() {
    _api.clearCache();
    _searchCache.clear();
  }

  @override
  bool get isLoggedIn => _api.isLoggedIn;

  @override
  String get currentUsername => _api.currentUsername;

  @override
  Listenable get collectionChanges => _collectionChanges;

  @override
  int effectiveSubjectCollectionCount(String username, int serverCount) {
    final count = _subjectCollectionCounts.putIfAbsent(
      username,
      () => _CollectionCount(serverCount),
    );
    return count.value(serverCount);
  }

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
    return (await fetchSubjectPage(type: type, sort: sort, page: page)).items;
  }

  @override
  Future<Paged<Subject>> fetchSubjectPage({
    required int type,
    required String sort,
    int page = 1,
  }) async {
    final json = await _api.get(
      'p1/subjects',
      query: {'type': '$type', 'sort': sort, 'page': '$page'},
    );
    return _pagedSubjects(
      json,
      fallbackOffset: (page - 1) * 20,
      fallbackLimit: 20,
    );
  }

  @override
  Future<List<Subject>> searchSubjects(String keyword, {int? type}) async {
    return (await searchSubjectPage(keyword, type: type)).items;
  }

  @override
  Future<Paged<Subject>> searchSubjectPage(
    String keyword, {
    int? type,
    int offset = 0,
  }) async {
    final key = '$currentUsername:$type:${keyword.trim()}:$offset';
    final hit = _searchCache[key];
    if (hit != null &&
        DateTime.now().difference(hit.at) < const Duration(minutes: 2)) {
      return hit.request;
    }
    final request = _searchSubjectPage(keyword.trim(), type, offset);
    if (_searchCache.length >= 40) _searchCache.remove(_searchCache.keys.first);
    _searchCache[key] = (at: DateTime.now(), request: request);
    try {
      return await request;
    } on Object {
      if (identical(_searchCache[key]?.request, request)) {
        _searchCache.remove(key);
      }
      rethrow;
    }
  }

  Future<Paged<Subject>> _searchSubjectPage(
    String keyword,
    int? type,
    int offset,
  ) async {
    final filter = <String, dynamic>{'nsfw': true};
    if (type != null && type > 0) filter['type'] = [type];
    final json = await _api.post(
      'p1/search/subjects',
      query: {'offset': '$offset', 'limit': '30'},
      body: {'keyword': keyword, 'filter': filter, 'sort': 'match'},
    );
    return _pagedSubjects(json, fallbackOffset: offset, fallbackLimit: 30);
  }

  @override
  Future<Subject> fetchSubject(int id) async {
    return Subject.fromJson(await _fetchSubjectJson(id));
  }

  @override
  Future<SubjectDetailData> fetchSubjectDetails(int id) async {
    final subjectJson = await _fetchSubjectJson(id);
    final errors = <String, String>{};
    final sections = <(String, Future<List<Object>> Function())>[
      (
        'episodes',
        () => _fetchItems(
          'p1/subjects/$id/episodes',
          SubjectEpisode.fromJson,
          100,
        ),
      ),
      ('previews', () async => const []),
      (
        'comments',
        () => _fetchItems(
          'p1/subjects/$id/comments',
          SubjectComment.fromJson,
          40,
        ),
      ),
      (
        'characters',
        () => _fetchItems(
          'p1/subjects/$id/characters',
          SubjectCharacter.fromJson,
          100,
        ),
      ),
      (
        'staffs',
        () => _fetchItems(
          'p1/subjects/$id/staffs/persons',
          SubjectStaff.fromJson,
          100,
        ),
      ),
      (
        'relations',
        () => _fetchItems(
          'p1/subjects/$id/relations',
          SubjectRelation.fromJson,
          100,
        ),
      ),
      (
        'indexes',
        () => _fetchItems('p1/subjects/$id/indexes', SubjectIndex.fromJson, 40),
      ),
      (
        'reviews',
        () =>
            _fetchItems('p1/subjects/$id/reviews', SubjectReview.fromJson, 20),
      ),
      (
        'topics',
        () => _fetchItems('p1/subjects/$id/topics', SubjectTopic.fromJson, 40),
      ),
    ];
    final results = await Future.wait(
      sections.map(
        (section) =>
            _safeItems(section.$2(), errors: errors, section: section.$1),
      ),
    );

    return SubjectDetailData.fromSubjectJson(
      json: subjectJson,
      sectionErrors: Map.unmodifiable(errors),
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
  Future<void> createTopicReply(Topic topic, String content) async {
    final value = content.trim();
    if (value.isEmpty) throw const ApiException('评论内容不能为空');
    if (topic.type != 'group' && topic.type != 'subject') {
      throw const ApiException('该类型暂不支持发表评论');
    }
    final formHash = _api.formHash;
    if (!_api.isLoggedIn || formHash.isEmpty) {
      throw const ApiException('请先登录后再发表评论');
    }
    final owner = topic.type == 'group' ? 'group' : 'subject';
    final json = await _api.postWebForm(
      '$owner/topic/${topic.id}/new_reply?ajax=1',
      referer: 'https://bgm.tv/$owner/topic/${topic.id}',
      fields: {
        'lastview': '',
        'formhash': formHash,
        'content': value,
        'submit': 'submit',
      },
    );
    _requireReplyConfirmation(json);
  }

  @override
  Future<UserProfileData> fetchUserProfile(String username) async {
    final errors = <String, String>{};
    final encoded = Uri.encodeComponent(username);
    final results = await Future.wait<dynamic>([
      _api.get('p1/users/$encoded'),
      _safeJson(
        _api.get('p1/users/$encoded/timeline', query: {'limit': '20'}),
        const [],
        errors: errors,
        section: 'timeline',
      ),
      _safeJson(
        _api.get(
          'p1/users/$encoded/collections/subjects',
          query: {'limit': '100'},
        ),
        const {},
        errors: errors,
        section: 'collections',
      ),
      _safeJson(
        _api.get(
          'p1/users/$encoded/collections/characters',
          query: {'limit': '40'},
        ),
        const {},
        errors: errors,
        section: 'characters',
      ),
      _safeJson(
        _api.get(
          'p1/users/$encoded/collections/persons',
          query: {'limit': '40'},
        ),
        const {},
        errors: errors,
        section: 'persons',
      ),
      _safeJson(
        _api.get('p1/users/$encoded/blogs', query: {'limit': '30'}),
        const {},
        errors: errors,
        section: 'blogs',
      ),
      _safeJson(
        _api.get('p1/users/$encoded/indexes', query: {'limit': '30'}),
        const {},
        errors: errors,
        section: 'indexes',
      ),
      _safeJson(
        _api.get('p1/users/$encoded/friends', query: {'limit': '50'}),
        const {},
        errors: errors,
        section: 'friends',
      ),
    ]);
    if (results.first is! Map) throw const ApiException('用户资料格式不正确');
    final user = CommunityUser.fromJson(
      Map<String, dynamic>.from(results[0] as Map),
    );
    _subjectCollectionCounts
        .putIfAbsent(user.username, () => _CollectionCount(user.stats.subjects))
        .reconcile(user.stats.subjects);
    return UserProfileData(
      sectionErrors: Map.unmodifiable(errors),
      user: user,
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
    final errors = <String, String>{};
    final results = await Future.wait<dynamic>([
      _api.get('p1/characters/$id'),
      _safeJson(
        _api.get('p1/characters/$id/casts', query: {'limit': '100'}),
        const {},
        errors: errors,
        section: 'works',
      ),
      _safeJson(
        _api.get('p1/characters/$id/collects', query: {'limit': '50'}),
        const {},
        errors: errors,
        section: 'collectors',
      ),
      _safeJson(
        _api.get('p1/characters/$id/comments'),
        const [],
        errors: errors,
        section: 'comments',
      ),
      _safeJson(
        _api.get('p1/characters/$id/indexes', query: {'limit': '40'}),
        const {},
        errors: errors,
        section: 'indexes',
      ),
    ]);
    if (results.first is! Map) throw const ApiException('角色资料格式不正确');
    return CharacterDetailData(
      sectionErrors: Map.unmodifiable(errors),
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
    _requireReplyConfirmation(json);
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
    final username = currentUsername;
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
    if (wasCollected != (type > 0) && username.isNotEmpty) {
      _subjectCollectionCounts
          .putIfAbsent(username, () => _CollectionCount(null))
          .change(type > 0 ? 1 : -1);
    }
    invalidateCache();
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
    final errors = <String, String>{};
    final results = await Future.wait<dynamic>([
      _api.get('p1/persons/$id'),
      _safeJson(
        _api.get('p1/persons/$id/comments'),
        const [],
        errors: errors,
        section: 'comments',
      ),
    ]);
    if (results.first is! Map) throw const ApiException('制作人员资料格式不正确');
    return PersonDetailData(
      sectionErrors: Map.unmodifiable(errors),
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

  Paged<Subject> _pagedSubjects(
    dynamic json, {
    required int fallbackOffset,
    required int fallbackLimit,
  }) {
    final map = json is Map ? json : const {};
    return Paged(
      items: _subjectPage(json),
      offset: (map['offset'] as num?)?.toInt() ?? fallbackOffset,
      limit: (map['limit'] as num?)?.toInt() ?? fallbackLimit,
      total: (map['total'] as num?)?.toInt(),
    );
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
    if (data is! List) throw const ApiException('区块列表数据格式不正确');
    return data
        .whereType<Map>()
        .map((item) => parser(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<Object>> _safeItems<T>(
    Future<List<T>> request, {
    Map<String, String>? errors,
    String? section,
  }) async {
    try {
      return (await request).cast<Object>();
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 429) rethrow;
      debugPrint('可选区块加载失败：${error.message}');
      if (errors != null && section != null) errors[section] = '$error';
      return const [];
    } on Object catch (error) {
      debugPrint('可选区块解析失败：${error.runtimeType}');
      if (errors != null && section != null) errors[section] = '数据解析失败，请稍后重试';
      return const [];
    }
  }

  /// 只接受站点明确的发布确认，未知响应不能作为成功。
  void _requireReplyConfirmation(dynamic json) {
    if (json is Map && json['status'] == 'error') {
      throw ApiException('${json['msg'] ?? json['message'] ?? '评论发布失败'}');
    }
    if (json is! Map || !(json['status'] == 'ok' || json['posts'] is Map)) {
      throw const ApiException('未收到评论发布确认，请刷新确认后再试');
    }
  }

  Future<dynamic> _safeJson(
    Future<dynamic> request,
    dynamic fallback, {
    Map<String, String>? errors,
    String? section,
  }) async {
    try {
      final result = await request;
      final items = result is Map ? result['data'] ?? result['result'] : result;
      if (items is! List) throw const ApiException('区块列表数据格式不正确');
      return result;
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 429) rethrow;
      debugPrint('可选区块加载失败：${error.message}');
      if (errors != null && section != null) errors[section] = '$error';
      return fallback;
    } on Object catch (error) {
      debugPrint('可选区块解析失败：${error.runtimeType}');
      if (errors != null && section != null) errors[section] = '数据解析失败，请稍后重试';
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
    previewService.dispose();
    _collectionChanges.dispose();
    _api.close();
  }
}

class _CollectionCount {
  _CollectionCount(this._server);
  int? _server;
  int _delta = 0;
  DateTime? _changedAt;
  int value(int server) {
    if (_server == null) {
      // 未读取总数时，新增只提供下界；取消仍需在已有总数上扣减。
      _server = server;
      if (_delta > 0 && server > 0) _delta = 0;
    }
    return ((_server ?? 0) + _delta).clamp(0, 1 << 30);
  }

  void change(int delta) {
    _delta += delta;
    _changedAt = DateTime.now();
  }

  void reconcile(int server) {
    final expected = (_server ?? server) + _delta;
    if (_server == null ||
        _delta == 0 ||
        (_delta > 0 ? server >= expected : server <= expected) ||
        (_changedAt != null &&
            DateTime.now().difference(_changedAt!) >
                const Duration(seconds: 30))) {
      _server = server;
      _delta = 0;
    }
  }
}
