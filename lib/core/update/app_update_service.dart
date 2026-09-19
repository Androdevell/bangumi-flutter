import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/platform_http_client.dart';

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
  AppUpdateService({http.Client? client})
    : _client = client,
      _ownsClient = client == null;

  static final _latestReleaseUri = Uri.parse(
    'https://api.github.com/repos/Androdevell/bangumi-flutter/releases/latest',
  );

  http.Client? _client;
  final bool _ownsClient;

  http.Client get _httpClient => _client ??= createPlatformHttpClient();

  Future<String> currentVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  Future<AppUpdateResult> check() async {
    final current = await currentVersion();
    final response = await _httpClient
        .get(
          _latestReleaseUri,
          headers: const {
            HttpHeaders.acceptHeader: 'application/vnd.github+json',
            HttpHeaders.userAgentHeader: 'BangumiFlutter/1.1.3',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == HttpStatus.notFound) {
      throw const AppUpdateException('GitHub 上还没有发布 Release');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppUpdateException('GitHub 返回 ${response.statusCode}，请稍后重试');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map) throw const AppUpdateException('版本信息格式不正确');
    final tag = '${json['tag_name'] ?? ''}'.trim();
    final latest = tag.replaceFirst(RegExp(r'^[vV]'), '');
    final releaseUrl = Uri.tryParse('${json['html_url'] ?? ''}');
    if (latest.isEmpty) throw const AppUpdateException('Release 未填写版本号');
    return AppUpdateResult(
      currentVersion: current,
      latestVersion: latest,
      releaseUrl: releaseUrl,
      updateAvailable: _compareVersions(latest, current) > 0,
    );
  }

  Future<bool> openRelease(AppUpdateResult result) async {
    final uri = result.releaseUrl;
    if (uri == null) return false;
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

int _compareVersions(String left, String right) {
  List<int> parts(String value) =>
      value
          .split(RegExp(r'[+-]'))
          .first
          .split('.')
          .map((item) => int.tryParse(item) ?? 0)
          .toList();

  final a = parts(left);
  final b = parts(right);
  final length = a.length > b.length ? a.length : b.length;
  for (var index = 0; index < length; index++) {
    final av = index < a.length ? a[index] : 0;
    final bv = index < b.length ? b[index] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}
