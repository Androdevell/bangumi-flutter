import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/localization/app_localizations.dart';

/// 显式官网操作使用浏览器标签，避免 Android 支持链接再次进入本应用。
Future<void> openWebsite(BuildContext context, Uri uri) async {
  try {
    if (Platform.isAndroid &&
        !await supportsLaunchMode(LaunchMode.inAppBrowserView)) {
      throw StateError('Browser tabs unavailable');
    }
    if (!await launchUrl(
      uri,
      mode:
          Platform.isAndroid
              ? LaunchMode.inAppBrowserView
              : LaunchMode.externalApplication,
    )) {
      throw StateError('Browser unavailable');
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).t('websiteOpenFailed')),
        ),
      );
    }
  }
}
