import 'dart:io';

import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows DPAPI vault encrypts and restores a value', () async {
    if (!Platform.isWindows) return;
    final vault = PlatformSecureVault();
    final key = 'bangumi.test.${DateTime.now().microsecondsSinceEpoch}';
    addTearDown(() => vault.delete(key));

    await vault.write(key, 'sensitive-session-value');

    expect(await vault.read(key), 'sensitive-session-value');
    await vault.delete(key);
    expect(await vault.read(key), isNull);
  });
}
