import 'package:bangumi_flutter/app/bangumi_app.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/core/community_models.dart';
import 'package:bangumi_flutter/core/subject_detail_models.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the adaptive Bangumi shell', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(BangumiApp(repository: _FakeRepository()));
    await tester.pumpAndSettle();

    expect(find.text('发现'), findsWidgets);
    expect(find.text('今日放送'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}

class _FakeRepository implements BangumiRepository {
  @override
  final Listenable collectionChanges = ChangeNotifier();

  @override
  int get pendingSubjectCollectionDelta => 0;

  @override
  bool get isLoggedIn => false;

  @override
  String get currentUsername => '';
  static const subject = Subject(
    id: 1,
    title: '测试动画',
    subtitle: 'TV · 2026-09-13',
    score: 8.5,
    episodes: 12,
    type: 2,
  );

  @override
  Future<Map<String, List<Subject>>> fetchCalendar() async => {
    'Mon': [subject],
    'Tue': [subject],
    'Wed': [subject],
    'Thu': [subject],
    'Fri': [subject],
    'Sat': [subject],
    'Sun': [subject],
  };

  @override
  Future<List<Subject>> fetchSubjects({
    required int type,
    required String sort,
    int page = 1,
  }) async => [subject];

  @override
  Future<Subject> fetchSubject(int id) async => subject;

  @override
  Future<SubjectDetailData> fetchSubjectDetails(int id) async =>
      const SubjectDetailData(
        subject: subject,
        infobox: [],
        tags: [],
        ratingDistribution: [],
        collectionCounts: {},
        episodes: [],
        previews: [],
        comments: [],
        characters: [],
        staffs: [],
        relations: [],
        indexes: [],
        reviews: [],
        topics: [],
      );

  @override
  Future<List<TimelineEntry>> fetchTimeline({
    String mode = 'all',
    int? category,
  }) async => [];

  @override
  Future<List<Topic>> fetchTopics({String type = 'all'}) async => [];

  @override
  Future<TopicDetailData> fetchTopicDetails(Topic topic) =>
      throw UnimplementedError();

  @override
  Future<List<Subject>> fetchTrending({int type = 2, int limit = 20}) async => [
    subject,
  ];

  @override
  Future<List<Subject>> searchSubjects(String keyword, {int? type}) async => [
    subject,
  ];

  @override
  Future<UserProfileData> fetchUserProfile(String username) =>
      throw UnimplementedError();

  @override
  Future<CharacterDetailData> fetchCharacterDetails(int id) =>
      throw UnimplementedError();

  @override
  Future<PersonDetailData> fetchPersonDetails(int id) =>
      throw UnimplementedError();

  @override
  Future<List<CommunityReply>> fetchEpisodeComments(int episodeId) async => [];

  @override
  Future<void> createEpisodeComment(int episodeId, String content) async {}

  @override
  Future<List<CommunityReply>> fetchPersonComments(int personId) async => [];

  @override
  Future<void> updateSubjectCollection(
    int subjectId, {
    required int type,
    required int rate,
    required String comment,
    required bool isPrivate,
    bool wasCollected = true,
  }) async {}

  @override
  Future<void> updateEpisodeProgress(
    int episodeId,
    int type, {
    bool batch = false,
  }) async {}

  @override
  Future<void> toggleCharacterCollection(
    int characterId,
    bool collected,
  ) async {}

  @override
  Future<void> toggleFriend(String username, bool isFriend) async {}

  @override
  Future<void> setEpisodeCommentReaction(int commentId, String? value) async {}

  @override
  Future<void> setSubjectCommentReaction(int commentId, String? value) async {}

  @override
  Future<void> setTopicPostReaction(
    String topicType,
    int postId,
    String? value,
  ) async {}

  @override
  Future<void> setTimelineReaction(int timelineId, String? value) async {}

  @override
  void close() {}
}
