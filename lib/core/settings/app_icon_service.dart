import 'package:flutter/services.dart';

import 'app_preferences.dart';

abstract final class AppIconService {
  static const _channel = MethodChannel('com.bgm.irena/app-icon');

  static Future<bool> apply(AppIconStyle style) async {
    try {
      return await _channel.invokeMethod<bool>('setAppIcon', {
            'style': style.name,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
