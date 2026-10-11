import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';

/// 仅在服务端确认写入成功后发布，前后状态来自读取而非 UI 猜测。
@immutable
class CollectionChanged {
  CollectionChanged({
    required this.session,
    required this.subjectId,
    required this.previousStatus,
    required this.nextStatus,
    required this.revision,
    required Set<String> fields,
  }) : fields = Set.unmodifiable(fields);

  final SessionScope session;
  final int subjectId;
  final int previousStatus;
  final int nextStatus;
  final int revision;
  final Set<String> fields;
}
