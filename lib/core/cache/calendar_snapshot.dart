import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../auth/secure_vault.dart';
import '../models.dart';

@immutable
class ComposeCalendarSnapshot {
  ComposeCalendarSnapshot(Map<String, List<Subject>> calendar, this.savedAt)
    : calendar = Map.unmodifiable(
        calendar.map(
          (key, value) => MapEntry(key, List<Subject>.unmodifiable(value)),
        ),
      );
  final Map<String, List<Subject>> calendar;
  final DateTime savedAt;
}

/// 仅保存匿名日历，环境与格式版本隔离，不保存会话或用户字段。
class CalendarSnapshotStore {
  CalendarSnapshotStore(this.vault, this.environment);
  final SecureVault vault;
  final String environment;
  static const key = 'app.cache.publicCalendar.v1';
  Future<({Map<String, dynamic> data, DateTime at})?> read() async {
    try {
      final raw = await vault.read(key);
      if (raw == null || raw.length > 512 * 1024) return null;
      final value = jsonDecode(raw);
      if (value is! Map ||
          value['version'] != 1 ||
          value['environment'] != environment ||
          value['data'] is! Map) {
        return null;
      }
      final at = DateTime.tryParse('${value['at']}');
      if (at == null ||
          at.isAfter(DateTime.now()) ||
          DateTime.now().difference(at) > const Duration(days: 3)) {
        return null;
      }
      return (data: Map<String, dynamic>.from(value['data'] as Map), at: at);
    } on Object {
      return null;
    }
  }

  Future<void> write(Map data) async {
    final raw = jsonEncode({
      'version': 1,
      'environment': environment,
      'at': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    });
    if (raw.length <= 512 * 1024) await vault.write(key, raw);
  }
}
