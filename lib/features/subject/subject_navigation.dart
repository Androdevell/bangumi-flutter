import 'package:flutter/material.dart';
import '../../core/models.dart';
import '../../data/bangumi_repository.dart';
import 'subject_detail_page.dart';

Future<void> openSubjectDetails(
  BuildContext context, {
  required Subject subject,
  required BangumiRepository repository,
  required String heroTag,
}) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    pageBuilder:
        (_, animation, __) => SubjectDetailPage(
          subject: subject,
          repository: repository,
          heroTag: heroTag,
        ),
    transitionsBuilder:
        (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
    transitionDuration: const Duration(milliseconds: 300),
  ),
);
