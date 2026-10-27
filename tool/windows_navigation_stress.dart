// Anonymous release benchmark of the real calendar, cards and details routes.
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:bangumi_flutter/core/cache/managed_image_file_system.dart';
import 'package:flutter/material.dart';
import 'package:bangumi_flutter/app/bangumi_app.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/settings/app_preferences.dart';
import 'package:bangumi_flutter/core/network/app_image_cache.dart';
import 'package:bangumi_flutter/core/network/image_transport.dart';
import 'package:bangumi_flutter/core/network/platform_http_client.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/features/subject/subject_detail_page.dart';
import 'package:bangumi_flutter/widgets/subject_card.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/core/settings/theme_preferences.dart';
import 'package:bangumi_flutter/core/diagnostics/image_diagnostics.dart';

const steps = int.fromEnvironment('STRESS_STEPS', defaultValue: 300);

List<Element> elements(bool Function(Element) test) {
  final result = <Element>[];
  void visit(Element element) {
    if (test(element)) result.add(element);
    element.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  return result;
}

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  final imageClient = ImageTransport(createPlatformHttpClient());
  AppImageCache.initialize(
    imageClient,
    cacheKey: 'bangumiNavigationStressV1',
    fileSystem: ManagedImageFileSystem(
      key: 'bangumiNavigationStressV1/images',
      legacy:
          () async => Directory(
            '${(await getTemporaryDirectory()).path}/bangumiNavigationStressV1',
          ),
    ),
  );
  final repository = _StressRepository(); // No AuthService or saved session.
  runApp(
    BangumiApp(
      repository: repository,
      preferences: AppPreferences(MemorySecureVault()),
      initialTheme: ComposeThemePreferences(
        style:
            arguments.contains('--stress-glass')
                ? InterfaceStyle.liquidGlass
                : InterfaceStyle.material,
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(
      run(
        repository,
        imageClient.close,
        cold: arguments.contains('--stress-cold'),
      ),
    ),
  );
}

Future<void> run(
  RemoteBangumiRepository repository,
  VoidCallback closeImages, {
  required bool cold,
}) async {
  final deadline = Timer(const Duration(minutes: 7), () => exit(2));
  try {
    await ImageDiagnostics.instance.open(
      File('${Directory.systemTemp.path}/bangumi-navigation-$pid.jsonl'),
    );
    if (cold) await AppImageCache.manager.emptyCache();
    for (var wait = 0; wait < 60; wait++) {
      if (elements((e) => e.widget is SubjectCard).isNotEmpty) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (elements((e) => e.widget is SubjectCard).isEmpty) {
      throw StateError('Calendar did not load');
    }
    var routes = 0;
    for (var step = 0; step < steps; step++) {
      final chips = elements((e) => e.widget is ChoiceChip);
      if (chips.length != 7) throw StateError('Expected seven real day chips');
      final day = step < 100 ? step % 2 : step % 7;
      (chips[day].widget as ChoiceChip).onSelected!(true);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (step % 50 == 49) {
        final cards = elements((e) => e.widget is SubjectCard);
        if (cards.isEmpty) throw StateError('No real cards');
        (cards.first.widget as SubjectCard).onTap();
        await Future<void>.delayed(const Duration(seconds: 2));
        final pages = elements((e) => e.widget is SubjectDetailPage);
        if (pages.length != 1) throw StateError('Details route missing');
        for (final element in elements(
          (e) => e is StatefulElement && e.state is ScrollableState,
        )) {
          final state = (element as StatefulElement).state as ScrollableState;
          final scrollContext = state.context;
          if (!scrollContext.mounted) continue;
          if (ModalRoute.of(scrollContext)?.isCurrent == true &&
              state.position.hasContentDimensions &&
              state.position.axis == Axis.vertical) {
            state.position.jumpTo(
              state.position.maxScrollExtent.clamp(0.0, 400.0),
            );
          }
        }
        if (!pages.single.mounted) throw StateError('Details was disposed');
        Navigator.of(pages.single).pop();
        routes++;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      if (step % 25 == 24) {
        stdout.writeln(
          'NAVIGATION steps=${step + 1} routes=$routes cache=${PaintingBinding.instance.imageCache.currentSize}',
        );
      }
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    final counts = ImageDiagnostics.instance.snapshot['counts'] as Map;
    if ((counts['failed'] as int? ?? 0) == 0 ||
        (counts['cleanupFinished'] as int? ?? 0) == 0) {
      throw StateError('Image failure and cleanup paths were not exercised');
    }
    await ImageDiagnostics.instance.flush();
    stdout.writeln(
      'NAVIGATION COUNTS ${ImageDiagnostics.instance.snapshot['counts']}',
    );
    stdout.writeln('NAVIGATION PASS steps=$steps cold=$cold');
    deadline.cancel();
    repository.close();
    await AppImageCache.dispose();
    closeImages();
    exit(0);
  } catch (error) {
    stderr.writeln('NAVIGATION FAIL ${error.runtimeType}');
    deadline.cancel();
    exit(1);
  }
}

class _StressRepository extends RemoteBangumiRepository {
  @override
  Future<Map<String, List<Subject>>> fetchCalendar() async {
    final calendar = await super.fetchCalendar();
    return calendar.map(
      (day, subjects) => MapEntry(day, [
        const Subject(
          id: 710874,
          title: 'Oversized cover regression',
          type: 2,
          imageUrl: 'https://lain.bgm.tv/pic/cover/l/75/89/710874_99X5Q.jpg',
        ),
        ...subjects,
      ]),
    );
  }
}
