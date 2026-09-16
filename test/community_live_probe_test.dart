import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _runLiveTests = bool.fromEnvironment('RUN_LIVE_BGM_TESTS');

void main() {
  test(
    'user, character and episode comment APIs match the live models',
    () async {
      final repository = RemoteBangumiRepository();
      addTearDown(repository.close);

      final user = await repository.fetchUserProfile('sai');
      final character = await repository.fetchCharacterDetails(1);
      final comments = await repository.fetchEpisodeComments(9122);
      final topics = await repository.fetchTopics(type: 'group');
      final topic = await repository.fetchTopicDetails(topics.first);

      expect(user.user.username, 'sai');
      expect(user.user.stats.subjects, greaterThan(0));
      expect(user.collections, isNotEmpty);
      expect(user.friends, isNotEmpty);
      expect(character.character.name, isNotEmpty);
      expect(character.works, isNotEmpty);
      expect(character.collectors, isNotEmpty);
      expect(character.comments, isNotEmpty);
      expect(comments, isNotEmpty);
      expect(comments.first.user.username, isNotEmpty);
      expect(topic.title, isNotEmpty);
      expect(topic.replies, isNotEmpty);
    },
    skip: _runLiveTests ? false : 'Live network probe',
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
