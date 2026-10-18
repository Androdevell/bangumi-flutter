import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';

abstract final class PrivacyAudience {
  static const all = 'all';
  static const friends = 'friends';
  static const none = 'none';
  static const values = [all, friends, none];
}

abstract final class PrivacyField {
  static const privateMessage = 'privateMessage';
  static const timelineReply = 'timelineReply';
  static const timelineCollectReply = 'timelineCollectReply';
  static const follow = 'follow';
  static const mentionNotification = 'mentionNotification';
  static const commentNotification = 'commentNotification';
  static const friendNotification = 'friendNotification';
  static const values = [
    privateMessage,
    timelineReply,
    timelineCollectReply,
    follow,
    mentionNotification,
    commentNotification,
    friendNotification,
  ];
  static List<String> options(String field) =>
      field == follow || field == friendNotification
          ? const [PrivacyAudience.all, PrivacyAudience.none]
          : PrivacyAudience.values;
}

@immutable
class ComposePrivacySettings {
  ComposePrivacySettings({
    required this.session,
    required Map<String, String> settings,
  }) : settings = Map.unmodifiable(settings);
  final SessionScope session;
  final Map<String, String> settings;

  factory ComposePrivacySettings.fromJson(Object? json, SessionScope scope) {
    if (json is! Map || json['settings'] is! Map) {
      throw const FormatException('Invalid privacy settings');
    }
    final source = json['settings'] as Map;
    final values = <String, String>{};
    for (final field in PrivacyField.values) {
      final value = source[field];
      if (value is! String || !PrivacyField.options(field).contains(value)) {
        throw const FormatException('Invalid privacy audience');
      }
      values[field] = value;
    }
    return ComposePrivacySettings(session: scope, settings: values);
  }
}
