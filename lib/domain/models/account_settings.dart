import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';

@immutable
class ComposeAccountSettings {
  ComposeAccountSettings({
    required this.session,
    required Map<String, String> fields,
    required Map<String, String> timezones,
    required Set<String> checkboxNames,
    required Map<String, int> maxLengths,
    Map<String, String> checkboxValues = const {},
    this.avatarUrl = '',
    this.sitePrefix = '',
    this.restrictedField,
  }) : fields = Map.unmodifiable(fields),
       timezones = Map.unmodifiable(timezones),
       checkboxNames = Set.unmodifiable(checkboxNames),
       maxLengths = Map.unmodifiable(maxLengths),
       checkboxValues = Map.unmodifiable(checkboxValues);
  final SessionScope session;
  final Map<String, String> fields, timezones;
  final Map<String, int> maxLengths;
  final Map<String, String> checkboxValues;
  final Set<String> checkboxNames;
  final String avatarUrl, sitePrefix;
  final String? restrictedField;
  String value(String key) => fields[key] ?? '';
  static const editableFields = {
    'nickname',
    'sign_input',
    'newsite',
    'newbio',
    'timeoffsetnew',
  };
}
