import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import '../media/rich_image_policy.dart';
import 'image_header.dart';
import 'image_request_headers.dart';
import 'bounded_response.dart';
import 'image_transfer_files.dart';
import '../diagnostics/image_diagnostics.dart';

/// 图片通道不使用 Cookie 会话，逐次检查重定向，并限制流式响应大小。
class SafeImageFileService extends FileService {
  SafeImageFileService(
    this.client, {
    Future<List<InternetAddress>> Function(String)? lookup,
    ImageTransferFiles? files,
    ImageDiagnostics? diagnostics,
    DateTime Function()? clock,
  }) : lookup = lookup ?? InternetAddress.lookup,
       _files = files ?? ImageTransferFiles(),
       diagnostics = diagnostics ?? ImageDiagnostics.instance,
       _clock = clock ?? DateTime.now;
  final http.Client client;
  final Future<List<InternetAddress>> Function(String) lookup;
  static const maxBytes = 20 * 1024 * 1024;
  final ImageTransferFiles _files;
  final ImageDiagnostics diagnostics;
  final DateTime Function() _clock;
  final _failures = <String, ({DateTime until, HttpException error})>{};

  void clearFailure(String url) => _failures.remove(url);
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final request = diagnostics.nextRequest;
    final cached = _failures[url];
    if (cached != null && cached.until.isAfter(_clock())) {
      diagnostics.record(ImageEvent.cooldown, request);
      throw cached.error;
    }
    _failures.remove(url);
    diagnostics.record(ImageEvent.request, request);
    try {
      final result = await _get(url, request, headers: headers);
      diagnostics.record(ImageEvent.ready, request);
      return result;
    } catch (error) {
      final category = switch (error) {
        HttpException(message: 'Image pixel limit exceeded') => 1,
        HttpException(message: 'Image format not recognized') => 2,
        HttpException(message: 'Image exceeds 20 MB') => 3,
        _ => 0,
      };
      diagnostics.record(ImageEvent.failed, request, category: category);
      if (category != 0 && error is HttpException) {
        if (_failures.length >= 128) _failures.remove(_failures.keys.first);
        _failures[url] = (
          until: _clock().add(const Duration(seconds: 30)),
          error: error,
        );
      }
      rethrow;
    }
  }

  Future<FileServiceResponse> _get(
    String url,
    int requestId, {
    Map<String, String>? headers,
  }) async {
    var uri = Uri.parse(url);
    for (var hop = 0; hop <= 5; hop++) {
      if (!ImageUrlSafety.valid(uri)) {
        throw const HttpException('Unsafe image URL');
      }
      final addresses = await lookup(
        uri.host,
      ).timeout(const Duration(seconds: 10));
      if (addresses.isEmpty ||
          addresses.any((a) => !ImageUrlSafety.publicAddress(a))) {
        throw const HttpException('Private image address');
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers.addAll(imageRequestHeaders(uri, headers));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 300 &&
          response.statusCode < 400 &&
          response.statusCode != 304) {
        await response.stream
            .take(1)
            .drain<void>()
            .timeout(const Duration(seconds: 10));
        final location = response.headers['location'];
        if (location == null) {
          throw const HttpException('Image redirect missing location');
        }
        uri = uri.resolve(location);
        continue;
      }
      if ((response.contentLength ?? 0) > maxBytes) {
        await response.stream.listen((_) {}).cancel();
        throw const HttpException('Image exceeds 20 MB');
      }
      final type = response.headers['content-type']?.split(';').first.trim();
      if (response.statusCode == 200 &&
          type != null &&
          !type.startsWith('image/') &&
          type != 'application/octet-stream') {
        await response.stream.listen((_) {}).cancel();
        throw const HttpException('Response is not an image');
      }
      Stream<List<int>> bounded() async* {
        var bytes = 0;
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 20),
        )) {
          bytes += chunk.length;
          if (bytes > maxBytes) {
            throw const HttpException('Image exceeds 20 MB');
          }
          yield chunk;
        }
      }

      if (response.statusCode != 200) {
        final small = await readBoundedResponse(response, maxBytes: 64 * 1024);
        return HttpGetResponse(
          http.StreamedResponse(
            Stream.value(small.bodyBytes),
            small.statusCode,
            headers: small.headers,
          ),
        );
      }
      final transfer = await _files.create(
        request: requestId,
        diagnostics: diagnostics,
      );
      await transfer.prepare(bounded(), _validateImage);

      return HttpGetResponse(
        http.StreamedResponse(
          transfer.read(),
          response.statusCode,
          headers: response.headers,
          contentLength: response.contentLength,
        ),
      );
    }
    throw const HttpException('Too many image redirects');
  }

  /// 读取的头部窗口；JPEG 的 SOF 可能被 EXIF 推到较后位置。
  static const _headerWindow = 64 * 1024;

  /// 单张图片允许的最大像素数。
  ///
  /// 此前为 24M 像素（6000×4000，解码约 96 MB），对封面极其宽松；
  /// 8M 像素可容纳 4K 剧照（3840×2160≈8.29M），又把单张解码压到 32 MB 以内。
  static const maxPixels = 8 * 1024 * 1024;

  /// 单边上限，避免 `1×10_000_000` 这类畸形尺寸绕过像素预算。
  static const _maxDimension = 8192;

  /// 用纯 Dart 解析尺寸；头部窗口无法确定时扩大到有界文件，拒绝未知尺寸。
  static Future<void> _validateImage(File file) async {
    // 只读窗口内字节；不足 24 字节同样由长度判断拒绝，省掉一次 length() 系统调用。
    final head = await _readHead(file, _headerWindow);
    if (head.length < 24) {
      throw const HttpException('Image format not recognized');
    }
    var header = parseImageHeader(head);
    if (header == null && hasImageMagic(head) && head.length == _headerWindow) {
      header = parseImageHeader(await _readHead(file, maxBytes));
    }
    if (header == null) {
      throw const HttpException('Image format not recognized');
    }
    if (header.width > _maxDimension ||
        header.height > _maxDimension ||
        header.pixels > maxPixels) {
      throw const HttpException('Image pixel limit exceeded');
    }
  }

  static Future<Uint8List> _readHead(File file, int count) async {
    final handle = await file.open();
    try {
      return await handle.read(count);
    } finally {
      await handle.close();
    }
  }
}
