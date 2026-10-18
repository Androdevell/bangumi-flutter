import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/network/api_client.dart';
import '../../../domain/models/privacy_settings.dart';
import '../../../domain/repositories/privacy_repository.dart';
import '../../../widgets/common.dart';
import 'privacy_controller.dart';

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key, required this.repository});
  final PrivacyRepository repository;
  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  late final PrivacyController _controller = PrivacyController(
    widget.repository,
  );
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

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.t('privacy'))),
      body: ContentFrame(
        maxWidth: 760,
        child: AnimatedBuilder(
          animation: _controller,
          builder:
              (context, _) => ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Text(strings.t('privacyDescription')),
                  const SizedBox(height: 16),
                  if (_controller.busy) const LinearProgressIndicator(),
                  if (_controller.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      strings.t(_errorKey(_controller.error!)),
                      key: const ValueKey('privacy-error'),
                    ),
                  ],
                  if (_controller.loaded) ...[
                    for (final field in PrivacyField.values)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(
                            'privacy-$field-${_controller.values[field]}',
                          ),
                          value: _controller.values[field],
                          decoration: InputDecoration(
                            labelText: strings.t('privacy_$field'),
                            border: const OutlineInputBorder(),
                          ),
                          isExpanded: true,
                          items: [
                            for (final option in PrivacyField.options(field))
                              DropdownMenuItem(
                                value: option,
                                child: Text(strings.t('privacy_$option')),
                              ),
                          ],
                          onChanged:
                              _controller.busy || _controller.uncertain
                                  ? null
                                  : (value) {
                                    if (value != null) {
                                      _controller.edit(field, value);
                                    }
                                  },
                        ),
                      ),
                  ],
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('privacy-save'),
                        onPressed:
                            _controller.canSave
                                ? () async {
                                  final saved = await _controller.save();
                                  if (saved && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          strings.t('privacySaved'),
                                        ),
                                      ),
                                    );
                                  }
                                }
                                : null,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(strings.t('save')),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('privacy-reload'),
                        onPressed: _controller.busy ? null : _controller.load,
                        icon: const Icon(Icons.refresh),
                        label: Text(strings.t('privacyReload')),
                      ),
                    ],
                  ),
                ],
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
