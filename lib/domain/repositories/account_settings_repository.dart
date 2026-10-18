import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';
import '../models/account_settings.dart';

abstract interface class AccountSettingsRepository {
  SessionScope get scope;
  Listenable get sessionChanges;
  Future<ComposeAccountSettings> load();
  Future<ComposeAccountSettings> save(
    ComposeAccountSettings original,
    Map<String, String> edits, {
    Uint8List? avatar,
  });
}

abstract interface class AccountSettingsFeature {
  AccountSettingsRepository get accountSettings;
}
