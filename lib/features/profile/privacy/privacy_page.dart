import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/network/api_client.dart';
import '../../../domain/models/privacy_settings.dart';
import '../../../domain/repositories/privacy_repository.dart';
import '../../../widgets/common.dart';
import '../../../widgets/settings_choice.dart';
import 'privacy_controller.dart';

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key, required this.repository});
  final PrivacyRepository repository;
  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  late final _controller = PrivacyController(widget.repository);
  bool _allowPop = false;
  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _discard() async {
    if (_controller.editCount == 0) return true;
    final s = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                content: Text(s.t('discardEdits')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(s.t('cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(s.t('confirm')),
                  ),
                ],
              ),
        ) ==
        true;
  }

  Future<void> _reload() async {
    if (!await _discard() || !mounted) return;
    await _controller.load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder:
          (context, _) => PopScope(
            canPop:
                _allowPop || (!_controller.busy && _controller.editCount == 0),
            onPopInvokedWithResult: (popped, _) async {
              if (popped || _controller.busy) return;
              if (await _discard() && mounted) {
                setState(() => _allowPop = true);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) Navigator.pop(context);
                });
              }
            },
            child: Scaffold(
              appBar: AppBar(title: Text(s.t('privacy'))),
              bottomNavigationBar: SafeArea(
                child: ContentFrame(
                  shrinkWrap: true,
                  maxWidth: 760,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_controller.editCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '${s.t('unsavedSettings')} · ${_controller.editCount}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              key: const ValueKey('privacy-save'),
                              onPressed:
                                  !_controller.canSave
                                      ? null
                                      : () async {
                                        if (await _controller.save() &&
                                            context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                s.t('privacySaved'),
                                              ),
                                            ),
                                          );
                                        }
                                      },
                              icon: const Icon(Icons.save_outlined),
                              label: Text(s.t('save')),
                            ),
                            OutlinedButton.icon(
                              key: const ValueKey('privacy-reload'),
                              onPressed: _controller.busy ? null : _reload,
                              icon: const Icon(Icons.refresh),
                              label: Text(s.t('privacyReload')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              body: ContentFrame(
                maxWidth: 760,
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Text(s.t('privacyDescription')),
                    const SizedBox(height: 16),
                    if (_controller.busy) const LinearProgressIndicator(),
                    if (_controller.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          s.t(_errorKey(_controller.error!)),
                          key: const ValueKey('privacy-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_controller.loaded) ...[
                      for (final group in [
                        PrivacyField.values.take(4),
                        PrivacyField.values.skip(4),
                      ]) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            s.t(
                              group.first == PrivacyField.privateMessage
                                  ? 'privacyContact'
                                  : 'privacyNotifications',
                            ),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        for (final field in group)
                          SettingsChoiceTile(
                            key: ValueKey(
                              'privacy-$field-${_controller.values[field]}',
                            ),
                            title: s.t('privacy_$field'),
                            value: _controller.values[field]!,
                            icon: Icons.shield_outlined,
                            options: {
                              for (final v in PrivacyField.options(field))
                                v: s.t('privacy_$v'),
                            },
                            onChanged:
                                _controller.busy || _controller.uncertain
                                    ? null
                                    : (v) => _controller.edit(field, v),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
    );
  }

  String _errorKey(Object error) {
    if (error is ApiException &&
        const {
          'privacyInvalid',
          'privacyConflict',
          'privacyUnconfirmed',
          'commentSessionChanged',
          'loginRequired',
          'fieldInvalid',
        }.contains(error.message)) {
      return error.message;
    }
    return 'privacyFailed';
  }
}
