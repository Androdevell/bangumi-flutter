import 'package:flutter/foundation.dart';
import '../../app/state/session_scope.dart';
import '../models/privacy_settings.dart';

abstract interface class PrivacyRepository {
  SessionScope get scope;
  Listenable get sessionChanges;
  Future<ComposePrivacySettings> load();
  Future<ComposePrivacySettings> save(
    ComposePrivacySettings original,
    Map<String, String> edits,
  );
}

abstract interface class PrivacyFeature {
  PrivacyRepository get privacy;
}
