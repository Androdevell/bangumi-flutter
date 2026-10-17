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
  MaterialPageRoute<void>(
    builder:
        (_) => SubjectDetailPage(
          subject: subject,
          repository: repository,
          heroTag: heroTag,
        ),
  ),
);
