import 'dart:convert';
import 'package:flutter/material.dart';

enum ThemeColorSource { preset, system, custom, image }

const themePresets = <String, Color>{
  'sakura': Color(0xFFE85D87),
  'iris': Color(0xFF7C6BC4),
  'ocean': Color(0xFF4D7EA8),
  'forest': Color(0xFF4F8068),
  'peach': Color(0xFFBE7754),
  'graphite': Color(0xFF547178),
};

@immutable
class ComposeThemePreferences {
  const ComposeThemePreferences({
    this.source = ThemeColorSource.preset,
    this.seed = const Color(0xFFE85D87),
    this.preset = 'sakura',
    this.mode = ThemeMode.system,
  });
  final ThemeColorSource source;
  final Color seed;
  final String preset;
  final ThemeMode mode;
  String encode() => jsonEncode({
    'schema': 1,
    'source': source.name,
    'seed': seed.toARGB32(),
    'preset': preset,
    'mode': mode.name,
  });
  static ComposeThemePreferences decode(String? raw) {
    try {
      final map = jsonDecode(raw ?? '') as Map;
      if (map['schema'] != 1) return const ComposeThemePreferences();
      return ComposeThemePreferences(
        source: ThemeColorSource.values.byName(map['source'] as String),
        seed: Color((map['seed'] as int) | 0xFF000000),
        preset:
            themePresets.containsKey(map['preset'])
                ? map['preset'] as String
                : 'sakura',
        mode: ThemeMode.values.byName(map['mode'] as String),
      );
    } on Object {
      return const ComposeThemePreferences();
    }
  }

  ComposeThemePreferences copyWith({
    ThemeColorSource? source,
    Color? seed,
    String? preset,
    ThemeMode? mode,
  }) => ComposeThemePreferences(
    source: source ?? this.source,
    seed: seed ?? this.seed,
    preset: preset ?? this.preset,
    mode: mode ?? this.mode,
  );
}
