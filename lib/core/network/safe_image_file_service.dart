import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import '../media/rich_image_policy.dart';
import 'image_request_headers.dart';
import 'bounded_response.dart';
import 'image_transfer_files.dart';

/// 图片通道不使用 Cookie 会话，逐次检查重定向，并限制流式响应大小。
class SafeImageFileService extends FileService {
  SafeImageFileService(
    this.client, {
    Future<List<InternetAddress>> Function(String)? lookup,
  }) : lookup = lookup ?? InternetAddress.lookup;
  final http.Client client;
  final Future<List<InternetAddress>> Function(String) lookup;
  static const maxBytes = 20 * 1024 * 1024;
  static final _files = ImageTransferFiles();
  @override
  Future<FileServiceResponse> get(
    String url, {
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
        throw const HttpException('Image exceeds 20 MB');
      }
      final type = response.headers['content-type']?.split(';').first.trim();
      if (response.statusCode == 200 &&
          type != null &&
          !type.startsWith('image/') &&
          type != 'application/octet-stream') {
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
      final file = await _files.create();
      try {
        final sink = file.openWrite();
        try {
          await sink.addStream(bounded());
        } finally {
          await sink.close();
        }
        final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
        ui.ImageDescriptor? descriptor;
        try {
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          if (descriptor.width <= 0 ||
              descriptor.height <= 0 ||
              descriptor.width * descriptor.height > 24 * 1024 * 1024) {
            throw const HttpException('Image pixel limit exceeded');
          }
        } finally {
          descriptor?.dispose();
          buffer.dispose();
        }
      } catch (_) {
        await _files.release(file);
        rethrow;
      }
      Stream<List<int>> content() async* {
        try {
          yield* file.openRead();
        } finally {
          await _files.release(file);
        }
      }

      return HttpGetResponse(
        http.StreamedResponse(
          content(),
          response.statusCode,
          headers: response.headers,
          contentLength: response.contentLength,
        ),
      );
    }
    throw const HttpException('Too many image redirects');
  }
}
