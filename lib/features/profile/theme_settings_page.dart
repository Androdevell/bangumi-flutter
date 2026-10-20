import '../../core/media/safe_image_thumbnail.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../app/theme_controller.dart';
import '../../app/app_theme.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/settings/theme_preferences.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_choice.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key, required this.controller});
  final ThemeController controller;
  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  late ComposeThemePreferences _draft = widget.controller.settings;
  late final _hex = TextEditingController(
    text: _draft.seed.toARGB32().toRadixString(16).substring(2).toUpperCase(),
  );
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _select(ComposeThemePreferences value) => setState(() {
    _draft = value;
    _error = null;
    _hex.text =
        value.seed.toARGB32().toRadixString(16).substring(2).toUpperCase();
  });
  Future<void> _image() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Images',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 20 * 1024 * 1024) throw const FormatException();
      final scheme = await ColorScheme.fromImageProvider(
        provider: MemoryImage(
          await safeImageThumbnail(await file.readAsBytes()),
        ),
      );
      if (mounted) {
        _select(
          _draft.copyWith(source: ThemeColorSource.image, seed: scheme.primary),
        );
      }
    } on Object {
      if (mounted) setState(() => _error = 'themeInvalid');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.controller.apply(_draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).t('themeSaved'))),
        );
      }
    } on Object {
      if (mounted) setState(() => _error = 'operationFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final preview =
        Theme.of(context).brightness == Brightness.dark
            ? AppTheme.dark(seed: _draft.seed)
            : AppTheme.light(seed: _draft.seed);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('themeColors'))),
      body: ContentFrame(
        maxWidth: 780,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SettingsChoiceTile(
              title: s.t('themeMode'),
              value: _draft.mode.name,
              options: {
                'system': s.t('themeAuto'),
                'light': s.t('themeLight'),
                'dark': s.t('themeDark'),
              },
              onChanged:
                  _busy
                      ? null
                      : (v) => _select(
                        _draft.copyWith(mode: ThemeMode.values.byName(v)),
                      ),
            ),
            SwitchListTile(
              title: Text(s.t('themeSystem')),
              subtitle: Text(
                '${s.t('themeSystemHint')}\n${s.t('themeFallback')}',
              ),
              value: _draft.source == ThemeColorSource.system,
              onChanged:
                  _busy
                      ? null
                      : (v) => _select(
                        _draft.copyWith(
                          source:
                              v
                                  ? ThemeColorSource.system
                                  : ThemeColorSource.preset,
                        ),
                      ),
            ),
            const SizedBox(height: 20),
            Text(
              s.t('themePreset'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final preset in themePresets.entries)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      backgroundColor: preset.value,
                      radius: 10,
                    ),
                    label: Text(s.t('theme_${preset.key}')),
                    selected:
                        _draft.source == ThemeColorSource.preset &&
                        _draft.preset == preset.key,
                    onSelected:
                        _busy
                            ? null
                            : (_) => _select(
                              _draft.copyWith(
                                source: ThemeColorSource.preset,
                                preset: preset.key,
                                seed: preset.value,
                              ),
                            ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _hex,
              enabled: !_busy,
              maxLength: 7,
              decoration: InputDecoration(
                labelText: s.t('themeSeed'),
                prefixIcon: const Icon(Icons.palette_outlined),
              ),
              onChanged: (v) {
                final raw = v.replaceFirst('#', '');
                if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(raw)) {
                  setState(() => _error = 'themeInvalid');
                  return;
                }
                setState(() {
                  _draft = _draft.copyWith(
                    source: ThemeColorSource.custom,
                    seed: Color(int.parse('FF$raw', radix: 16)),
                  );
                  _error = null;
                });
              },
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _image,
              icon: const Icon(Icons.image_outlined),
              label: Text(s.t('themeImage')),
            ),
            Text(
              s.t('themeImageHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Theme(
              data: preview,
              child: Builder(
                builder:
                    (context) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              s.t('themePreview'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed: () {},
                              child: Text(s.t('themeApply')),
                            ),
                            const LinearProgressIndicator(value: .6),
                          ],
                        ),
                      ),
                    ),
              ),
            ),
            if (_error != null)
              Text(
                s.t(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy || _error == 'themeInvalid' ? null : _apply,
              child: Text(s.t('themeApply')),
            ),
            TextButton(
              onPressed:
                  _busy ? null : () => _select(const ComposeThemePreferences()),
              child: Text(s.t('themeReset')),
            ),
          ],
        ),
      ),
    );
  }
}
