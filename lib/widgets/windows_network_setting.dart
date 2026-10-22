import 'dart:io';
import 'package:flutter/material.dart';
import '../core/auth/secure_vault.dart';
import '../core/localization/app_localizations.dart';
import '../core/network/platform_http_client.dart';
import '../core/settings/app_preferences.dart';

class WindowsNetworkSetting extends StatefulWidget {
  const WindowsNetworkSetting({super.key});
  @override
  State<WindowsNetworkSetting> createState() => _WindowsNetworkSettingState();
}

class _WindowsNetworkSettingState extends State<WindowsNetworkSetting> {
  WindowsNetworkMode selected = windowsNetworkMode;
  bool saving = false;
  Future<void> _save(WindowsNetworkMode? mode) async {
    if (mode == null || saving) return;
    setState(() => saving = true);
    try {
      await AppPreferences(PlatformSecureVault()).setNetworkMode(mode);
      if (mounted) setState(() => selected = mode);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).t('saveFailed'))),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();
    final s = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.route_outlined),
      title: Text(s.t('networkMode')),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButton<WindowsNetworkMode>(
            value: selected,
            isExpanded: true,
            items: [
              for (final mode in WindowsNetworkMode.values)
                DropdownMenuItem(
                  value: mode,
                  child: Text(
                    s.t(
                      mode == WindowsNetworkMode.direct
                          ? 'networkDirect'
                          : 'networkSystem',
                    ),
                  ),
                ),
            ],
            onChanged: saving ? null : _save,
          ),
          Text(s.t('networkRestart')),
        ],
      ),
    );
  }
}
