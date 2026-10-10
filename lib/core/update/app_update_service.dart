import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/platform_http_client.dart';

@immutable
class AppUpdateResult {
  const AppUpdateResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.updateAvailable,
  });

  final String currentVersion;
  final String latestVersion;
  final Uri? releaseUrl;
  final bool updateAvailable;
}

class AppUpdateService {
  AppUpdateService({
    http.Client? client,
    Future<String> Function()? versionProvider,
    this.includePrereleases = false,
  }) : _client = client,
       _versionProvider = versionProvider,
       _ownsClient = client == null;

  static final _latestReleaseUri = Uri.parse(
    'https://api.github.com/repos/Androdevell/bangumi-flutter/releases/latest',
  );

  http.Client? _client;
  final bool _ownsClient;
  final Future<String> Function()? _versionProvider;
  final bool includePrereleases;

  http.Client get _httpClient => _client ??= createPlatformHttpClient();

  Future<String> currentVersion() async {
    if (_versionProvider != null) return _versionProvider();
    final info = await PackageInfo.fromPlatform();
    if (info.version.contains('+') || info.buildNumber.isEmpty) {
      return info.version;
    }
    return '${info.version}+${info.buildNumber}';
  }

  Future<AppUpdateResult> check() async {
    final current = await currentVersion();
    final response = await _httpClient
        .get(
          _latestReleaseUri,
          headers: const {
            HttpHeaders.acceptHeader: 'application/vnd.github+json',
            HttpHeaders.userAgentHeader: 'BangumiFlutter/1.1.7',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == HttpStatus.notFound) {
      throw const AppUpdateException('GitHub 上还没有发布 Release');
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const AppUpdateException('GitHub 请求频率限制，请稍后再检查更新');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppUpdateException('GitHub 返回 ${response.statusCode}，请稍后重试');
    }
    dynamic json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on FormatException {
      throw const AppUpdateException('版本信息格式不正确');
    }
    if (json is! Map) throw const AppUpdateException('版本信息格式不正确');
    final tag = '${json['tag_name'] ?? ''}'.trim();
    final latest = tag.replaceFirst(RegExp(r'^[vV]'), '');
    final rawUrl = Uri.tryParse('${json['html_url'] ?? ''}');
    final releaseUrl = _isReleaseUrl(rawUrl) ? rawUrl : null;
    if (latest.isEmpty) throw const AppUpdateException('Release 未填写版本号');
    final newestVersion = _AppVersion.parse(latest);
    final currentParsed = _AppVersion.parse(current);
    if (newestVersion == null || currentParsed == null) {
      throw const AppUpdateException('Release 版本号格式不正确');
    }
    return AppUpdateResult(
      currentVersion: current,
      latestVersion: latest,
      releaseUrl: releaseUrl,
      updateAvailable:
          json['draft'] != true &&
          (includePrereleases ||
              (json['prerelease'] != true && newestVersion.pre.isEmpty)) &&
          newestVersion.compareTo(currentParsed) > 0,
    );
  }

  Future<bool> openRelease(AppUpdateResult result) async {
    final uri = result.releaseUrl;
    if (!_isReleaseUrl(uri) || !await canLaunchUrl(uri!)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void close() {
    if (_ownsClient) _client?.close();
  }
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

bool _isReleaseUrl(Uri? uri) =>
    uri != null &&
    uri.scheme == 'https' &&
    uri.host == 'github.com' &&
    uri.userInfo.isEmpty &&
    uri.port == 443 &&
    uri.path.toLowerCase().startsWith('/androdevell/bangumi-flutter/releases/');

class _AppVersion implements Comparable<_AppVersion> {
  _AppVersion(this.core, this.pre, this.build);
  final List<int> core;
  final List<String> pre;
  final int build;
  static _AppVersion? parse(String value) {
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$',
    ).firstMatch(value);
    if (match == null) return null;
    return _AppVersion(
      [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)],
      match.group(4)?.split('.') ?? [],
      int.tryParse(match.group(5) ?? '') ?? 0,
    );
  }

  @override
  int compareTo(_AppVersion other) {
    for (var i = 0; i < 3; i++) {
      final c = core[i].compareTo(other.core[i]);
      if (c != 0) return c;
    }
    if (pre.isEmpty != other.pre.isEmpty) return pre.isEmpty ? 1 : -1;
    for (var i = 0; i < pre.length || i < other.pre.length; i++) {
      if (i >= pre.length) return -1;
      if (i >= other.pre.length) return 1;
      final a = int.tryParse(pre[i]);
      final b = int.tryParse(other.pre[i]);
      final c =
          a != null && b != null
              ? a.compareTo(b)
              : a != null
              ? -1
              : b != null
              ? 1
              : pre[i].compareTo(other.pre[i]);
      if (c != 0) return c;
    }
    // 本项目将纯数字 +build 作为安装构建号，在 SemVer 优先级相同时比较。
    return build.compareTo(other.build);
  }
}
