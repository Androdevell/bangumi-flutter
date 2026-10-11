import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';

/// 环境、身份、权限版本、资源与规范化查询共同组成缓存键。
@immutable
class QueryKey {
  QueryKey({
    required this.environment,
    required this.session,
    required this.permissionRevision,
    required this.path,
    Map<String, String>? query,
  }) : parameters = _normalize(query);

  static const contractVersion = '2026-09-19-e170542';
  final String environment;
  final SessionScope session;
  final int permissionRevision;
  final String path;
  final String parameters;

  static String _normalize(Map<String, String>? query) {
    final keys = query?.keys.toList() ?? <String>[];
    keys.sort();
    return jsonEncode({for (final key in keys) key: query![key]});
  }

  @override
  bool operator ==(Object other) =>
      other is QueryKey &&
      other.environment == environment &&
      other.session == session &&
      other.permissionRevision == permissionRevision &&
      other.path == path &&
      other.parameters == parameters;

  @override
  int get hashCode =>
      Object.hash(environment, session, permissionRevision, path, parameters);
}
