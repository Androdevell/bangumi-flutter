import 'package:flutter/material.dart';

import '../core/localization/app_localizations.dart';
import '../core/network/third_party_preview_service.dart';

/// 设置页与预览页共用的授权开关，首次启用必须明确确认。
class ThirdPartyPreviewSetting extends StatefulWidget {
  const ThirdPartyPreviewSetting({super.key, required this.service});
  final ThirdPartyPreviewService service;

  @override
  State<ThirdPartyPreviewSetting> createState() =>
      _ThirdPartyPreviewSettingState();
}

class _ThirdPartyPreviewSettingState extends State<ThirdPartyPreviewSetting> {
  bool _busy = false;

  Future<void> _change(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final strings = AppLocalizations.of(context);
    try {
      if (value) {
        final accepted = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                scrollable: true,
                title: Text(strings.t('thirdPartyPreviews')),
                content: Text(strings.t('previewConsent')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(strings.t('cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(strings.t('previewAllow')),
                  ),
                ],
              ),
        );
        if (accepted != true || !mounted) return;
      }
      await widget.service.setEnabled(value);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.t('previewSaveFailed'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.service,
      builder:
          (context, _) => SwitchListTile(
            secondary: const Icon(Icons.photo_library_outlined),
            title: Text(strings.t('thirdPartyPreviews')),
            subtitle: Text(strings.t('previewSettingHint')),
            value: widget.service.enabled,
            onChanged: _busy ? null : _change,
          ),
    );
  }
}
