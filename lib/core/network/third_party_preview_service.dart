import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../subject_detail_models.dart';
import 'platform_http_client.dart';

enum PreviewFailure { network, unavailable, invalidResponse, saving }

class PreviewException implements Exception {
  const PreviewException(this.failure);
  final PreviewFailure failure;
}

/// 用户授权后才查询公开网页接口；客户端独立，不携带 Bangumi 登录信息。
class ThirdPartyPreviewService extends ChangeNotifier {
  ThirdPartyPreviewService({
    bool enabled = false,
    Future<void> Function(bool)? persist,
    http.Client Function()? clientFactory,
  }) : _enabled = enabled,
       _persist = persist,
       _clientFactory = clientFactory ?? createPlatformHttpClient;

  final Future<void> Function(bool)? _persist;
  final http.Client Function() _clientFactory;
  final Map<int, Future<List<SubjectPreview>>> _requests = {};
  http.Client? _client;
  bool _enabled;
  bool _disposed = false;
  int _generation = 0;
  int _permissionRevision = 0;
  Future<void> _saveQueue = Future.value();
  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    if (_disposed) return;
    final revision = ++_permissionRevision;
    // 关闭立即撤销权限；保存失败也不继续发送请求。
    if (!value) _revoke();
    final save = _saveQueue.then((_) async => await _persist?.call(value));
    _saveQueue = save.then<void>((_) {}, onError: (Object _) {});
    try {
      await save;
    } on Object {
      throw const PreviewException(PreviewFailure.saving);
    }
    if (_disposed || !value || revision != _permissionRevision) return;
    _enabled = true;
    _generation++;
    notifyListeners();
  }

  void _revoke() {
    _enabled = false;
    _generation++;
    _requests.clear();
    _client?.close();
    _client = null;
    notifyListeners();
  }

  bool _allowed(int generation) =>
      !_disposed && _enabled && generation == _generation;

  /// 仅在预览页被主动打开后调用，不随条目详情加载。
  Future<List<SubjectPreview>> fetch(Subject subject, {bool refresh = false}) {
    if (!_enabled || _disposed || !{2, 6}.contains(subject.type)) {
      return Future.value(const []);
    }
    if (refresh) _requests.remove(subject.id);
    if (_requests.length >= 32 && !_requests.containsKey(subject.id)) {
      _requests.remove(_requests.keys.first);
    }
    return _requests.putIfAbsent(subject.id, () {
      final generation = _generation;
      final request = _fetch(subject, generation);
      // 网络失败不缓存为永久结果；观察错误的分支也必须消费异常。
      request.then<void>(
        (_) {},
        onError: (Object error) {
          if (_allowed(generation) &&
              identical(_requests[subject.id], request)) {
            _requests.remove(subject.id);
          }
        },
      );
      return request;
    });
  }

  Future<Object?> _get(Uri uri, int generation) async {
    if (!_allowed(generation)) return null;
    final client = _client ??= _clientFactory();
    final request =
        http.Request('GET', uri)
          ..followRedirects = false
          ..headers.addAll(const {
            'Accept': 'application/json',
            'User-Agent': 'Mozilla/5.0',
            'Referer': 'https://m.douban.com/',
          });
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 12));
    if (!_allowed(generation)) return null;
    if (response.statusCode != 200) {
      throw const PreviewException(PreviewFailure.unavailable);
    }
    if ((response.contentLength ?? 0) > 2 * 1024 * 1024) {
      throw const PreviewException(PreviewFailure.invalidResponse);
    }
    final bytes = await response.stream
        .fold<BytesBuilder>(BytesBuilder(copy: false), (buffer, chunk) {
          if (!_allowed(generation)) return buffer;
          if (buffer.length + chunk.length > 2 * 1024 * 1024) {
            throw const PreviewException(PreviewFailure.invalidResponse);
          }
          buffer.add(chunk);
          return buffer;
        })
        .timeout(const Duration(seconds: 12));
    if (!_allowed(generation)) return null;
    try {
      return jsonDecode(utf8.decode(bytes.takeBytes()));
    } on FormatException {
      throw const PreviewException(PreviewFailure.invalidResponse);
    }
  }

  Future<List<SubjectPreview>> _fetch(Subject subject, int generation) async {
    try {
      Map? selected;
      final titles = {subject.title, subject.originalTitle}..remove('');
      final year = subject.airDate.split('-').first;
      for (final title in titles) {
        if (!_allowed(generation)) return const [];
        final suggestions = await _get(
          Uri.https('movie.douban.com', '/j/subject_suggest', {'q': title}),
          generation,
        );
        if (!_allowed(generation)) return const [];
        if (suggestions is! List) {
          throw const PreviewException(PreviewFailure.invalidResponse);
        }
        final matches = suggestions.whereType<Map>().where((item) {
          final id = '${item['id'] ?? ''}';
          return RegExp(r'^\d+$').hasMatch(id) &&
              titles.any(
                (name) =>
                    _normalize(name) == _normalize('${item['title'] ?? ''}') ||
                    _normalize(name) ==
                        _normalize('${item['sub_title'] ?? ''}'),
              ) &&
              (year.isEmpty || '${item['year'] ?? ''}' == year);
        });
        if (matches.isNotEmpty) {
          selected = matches.first;
          break;
        }
      }
      if (selected == null || !_allowed(generation)) return const [];
      final payload = await _get(
        Uri.https(
          'm.douban.com',
          '/rexxar/api/v2/movie/${selected['id']}/photos',
          {'start': '0', 'count': '24'},
        ),
        generation,
      );
      if (!_allowed(generation)) return const [];
      if (payload is! Map || payload['photos'] is! List) {
        throw const PreviewException(PreviewFailure.invalidResponse);
      }
      final photos = <SubjectPreview>[];
      for (final photo in (payload['photos'] as List).whereType<Map>()) {
        final image = photo['image'];
        if (image is! Map) continue;
        final normal = image['normal'];
        final large = image['large'];
        final normalUrl = _imageUrl(normal is Map ? normal['url'] : null);
        final largeUrl = _imageUrl(large is Map ? large['url'] : null);
        if (normalUrl.isEmpty && largeUrl.isEmpty) continue;
        photos.add(
          SubjectPreview(
            id: '${photo['id'] ?? photos.length}',
            imageUrl: normalUrl.isNotEmpty ? normalUrl : largeUrl,
            largeImageUrl: largeUrl.isNotEmpty ? largeUrl : normalUrl,
            width:
                large is Map && large['width'] is num
                    ? (large['width'] as num).toInt()
                    : 0,
            height:
                large is Map && large['height'] is num
                    ? (large['height'] as num).toInt()
                    : 0,
          ),
        );
        if (photos.length >= 24) break;
      }
      return List.unmodifiable(photos);
    } on Object catch (error) {
      if (!_allowed(generation)) return const [];
      if (error is PreviewException) rethrow;
      throw const PreviewException(PreviewFailure.network);
    }
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s·・:：]'), '');

  String _imageUrl(Object? value) {
    final uri = Uri.tryParse('$value');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.host != 'doubanio.com' && !uri.host.endsWith('.doubanio.com')) ||
        (uri.hasPort && uri.port != 443)) {
      return '';
    }
    return uri.toString();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _requests.clear();
    _client?.close();
    super.dispose();
  }
}
