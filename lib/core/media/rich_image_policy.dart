import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../auth/secure_vault.dart';
import '../text/emoji_catalog.dart';

enum ExternalImageMode { onDemand, automatic, blocked }

/// 评论图片偏好与剧照服务互不影响，仅保存域名和公开表情代码。
class RichImagePolicy extends ChangeNotifier {
  static final instance = RichImagePolicy();
  SecureVault? _vault;
  Future<void> _operations = Future.value();
  ExternalImageMode mode = ExternalImageMode.onDemand;
  final Set<String> allowedHosts = {};
  final List<String> recentEmojis = [];
  static const trustedHosts = {
    'lain.bgm.tv',
    'bgm.tv',
    'bangumi.tv',
    'chii.in',
  };
  static const _key = 'app.preference.commentMedia.v1';
  Future<void> initialize(SecureVault vault) async {
    _vault = vault;
    mode = ExternalImageMode.onDemand;
    allowedHosts.clear();
    recentEmojis.clear();
    try {
      final raw = await vault.read(_key);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map;
      mode = ExternalImageMode.values.firstWhere(
        (v) => v.name == data['mode'],
        orElse: () => ExternalImageMode.onDemand,
      );
      allowedHosts.addAll((data['hosts'] as List? ?? []).whereType<String>());
      recentEmojis.addAll(
        (data['recent'] as List? ?? [])
            .whereType<String>()
            .where((v) => EmojiCatalog.find(v) != null)
            .take(24),
      );
    } on Object {
      /* 损坏的偏好不阻断启动。 */
    }
    notifyListeners();
  }

  bool allows(Uri uri) =>
      trustedHosts.contains(uri.host) ||
      (mode != ExternalImageMode.blocked &&
          (mode == ExternalImageMode.automatic ||
              allowedHosts.contains(uri.host)));
  Future<void> setMode(ExternalImageMode value) async {
    mode = value;
    notifyListeners();
    await _save();
  }

  Future<void> allowHost(String host) async {
    allowedHosts.add(host);
    notifyListeners();
    await _save();
  }

  Future<void> resetHosts() async {
    allowedHosts.clear();
    notifyListeners();
    await _save();
  }

  Future<void> rememberEmoji(String code) async {
    if (EmojiCatalog.find(code) == null) return;
    recentEmojis
      ..remove(code)
      ..insert(0, code);
    if (recentEmojis.length > 24) {
      recentEmojis.removeRange(24, recentEmojis.length);
    }
    notifyListeners();
    await _save();
  }

  Future<void> _save() {
    final value = jsonEncode({
      'mode': mode.name,
      'hosts': allowedHosts.toList(),
      'recent': recentEmojis,
    });
    _operations = _operations
        .then((_) async {
          await _vault?.write(_key, value);
        })
        .catchError((Object _) {
          debugPrint('媒体偏好暂时无法保存');
        });
    return _operations;
  }
}

abstract final class ImageUrlSafety {
  static bool valid(Uri uri) {
    final address = InternetAddress.tryParse(uri.host);
    return uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.port == 443 &&
        uri.host != 'localhost' &&
        !uri.host.endsWith('.local') &&
        !uri.host.endsWith('.localhost') &&
        (!uri.host.contains(':')) &&
        (address != null
            ? publicAddress(address)
            : !RegExp(r'^[0-9.]+$').hasMatch(uri.host));
  }

  static bool publicAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
      return false;
    }
    final b = address.rawAddress;
    if (b.length == 4) {
      return !(b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127));
    }
    if (b.length != 16 || (b[0] & 0xfe) == 0xfc || b.every((v) => v == 0)) {
      return false;
    }
    if (b.take(10).every((v) => v == 0) && b[10] == 255 && b[11] == 255) {
      return publicAddress(
        InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12))),
      );
    }
    return true;
  }
}
