import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/navigation/bangumi_link.dart';
import '../core/models.dart';
import '../core/subject_detail_models.dart';
import '../core/localization/app_localizations.dart';
import '../data/bangumi_repository.dart';
import '../features/subject/subject_detail_page.dart';
import '../features/episode/episode_comments_page.dart';
import '../features/character/character_detail_page.dart';
import '../features/person/person_detail_page.dart';
import '../features/user/user_profile_page.dart';
import '../features/rakuen/topic_detail_page.dart';
import '../widgets/common.dart';
import '../features/browse/tag_page.dart';
import '../domain/repositories/tag_repository.dart';
import '../features/blog/blog_detail_page.dart';
import '../features/indexes/index_detail_page.dart';

class AppLinkScope extends InheritedWidget {
  const AppLinkScope({
    super.key,
    required this.repository,
    required super.child,
  });
  final BangumiRepository repository;
  static BangumiRepository? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLinkScope>()?.repository;
  @override
  bool updateShouldNotify(AppLinkScope oldWidget) =>
      oldWidget.repository != repository;
}

abstract final class AppLinkDispatcher {
  static final pending = ValueNotifier<String?>(null);
  static const channel = MethodChannel('com.bgm.irena/links');
  static String? _lastLink;
  static DateTime? _lastReceived;
  static void receive(String text) {
    final target = BangumiLinkParser.parse(text);
    if (target == null) return;
    final key = target.uri.toString();
    final now = DateTime.now();
    if (_lastLink == key &&
        _lastReceived != null &&
        now.difference(_lastReceived!) < const Duration(seconds: 1)) {
      return;
    }
    _lastLink = key;
    _lastReceived = now;
    pending.value = key;
  }

  static Future<void> initialize(List<String> arguments) async {
    for (final argument in arguments) {
      receive(argument);
    }
    channel.setMethodCallHandler((call) async {
      if (call.method == 'link' &&
          call.arguments is String &&
          BangumiLinkParser.parse(call.arguments as String) != null) {
        receive(call.arguments as String);
      }
    });
    if (Platform.isAndroid) {
      try {
        final initial = await channel.invokeMethod<String>('initialLink');
        if (initial != null && BangumiLinkParser.parse(initial) != null) {
          receive(initial);
        }
      } on MissingPluginException {
        /* 测试和不支持的宿主不注册入口。 */
      } on PlatformException {
        /* 链接入口不可用不阻止应用启动。 */
      }
    }
  }

  static Future<bool> open(BuildContext context, Uri uri) async {
    final target = BangumiLinkParser.parse('$uri');
    final repo = AppLinkScope.of(context);
    if (target == null || repo == null) return false;
    final id = int.tryParse(target.key) ?? 0;
    final page = switch (target.kind) {
      'subject' => SubjectDetailPage(
        subject: Subject(id: id, title: 'Bangumi'),
        heroTag: 'link-subject-$id',
        repository: repo,
      ),
      'ep' => _EpisodeLinkPage(id: id, repository: repo),
      'character' => CharacterDetailPage(characterId: id, repository: repo),
      'person' => PersonDetailPage(personId: id, repository: repo),
      'user' => UserProfilePage(username: target.key, repository: repo),
      'blog' => BlogDetailPage(id: id, repository: repo),
      'index' => IndexDetailPage(id: id, repository: repo),
      'tag' => TagPage(
        query: ComposeTagQuery(switch (target.uri.pathSegments.first) {
          'book' => 1,
          'music' => 3,
          'game' => 4,
          'real' => 6,
          _ => 2,
        }, target.key),
        repository: repo,
      ),
      'groupTopic' || 'subjectTopic' => TopicDetailPage(
        topic: Topic(
          id: id,
          type: target.kind == 'groupTopic' ? 'group' : 'subject',
          title: '',
          group: '',
          replies: 0,
          updatedAt: null,
        ),
        repository: repo,
      ),
      _ => null,
    };
    if (page == null) return false;
    unawaited(
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
    );
    return true;
  }

  static Future<void> prompt(BuildContext context) async {
    final s = AppLocalizations.of(context);
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder:
          (dialog) => AlertDialog(
            title: Text(s.t('openBgmLink')),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 8192,
              decoration: const InputDecoration(
                hintText: 'https://bgm.tv/subject/…',
              ),
              onSubmitted: (v) => Navigator.pop(dialog, v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(s.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, controller.text),
                child: Text(s.t('open')),
              ),
            ],
          ),
    );
    // 对话框退场动画结束前仍可能读取控制器。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (!context.mounted || input == null) return;
    final target = BangumiLinkParser.parse(input);
    if (target == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.t('invalidBgmLink'))));
      return;
    }
    await open(context, target.uri);
  }
}

class _EpisodeLinkPage extends StatefulWidget {
  const _EpisodeLinkPage({required this.id, required this.repository});
  final int id;
  final BangumiRepository repository;
  @override
  State<_EpisodeLinkPage> createState() => _EpisodeLinkPageState();
}

class _EpisodeLinkPageState extends State<_EpisodeLinkPage> {
  late Future<SubjectEpisode> episode = _load();
  Future<SubjectEpisode> _load() =>
      widget.repository is EpisodeMetadataRepository
          ? (widget.repository as EpisodeMetadataRepository).fetchEpisode(
            widget.id,
          )
          : Future.value(SubjectEpisode.fromJson({'id': widget.id}));
  @override
  Widget build(BuildContext context) => FutureBuilder<SubjectEpisode>(
    future: episode,
    builder: (context, snapshot) {
      if (snapshot.data != null) {
        return EpisodeCommentsPage(
          episode: snapshot.data!,
          repository: widget.repository,
        );
      }
      return Scaffold(
        appBar: AppBar(),
        body:
            snapshot.hasError
                ? NetworkErrorView(
                  error: snapshot.error!,
                  onRetry: () => setState(() => episode = _load()),
                )
                : const Center(child: CircularProgressIndicator()),
      );
    },
  );
}
