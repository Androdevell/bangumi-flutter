import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

/// 原生流式下载后只传临时文件路径，避免整张图片跨 MethodChannel 复制。
class AndroidImageFileService extends FileService {
  AndroidImageFileService() {
    concurrentFetches = 3;
  }
  static const _channel = MethodChannel('com.xiaoyv.bangumi/network');
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = await _channel.invokeMapMethod<
      String,
      dynamic
    >('downloadImage', {
      'url': url,
      'headers': {
        HttpHeaders.userAgentHeader:
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 BangumiFlutter/1.1.6',
        ...?headers,
      },
    });
    if (response == null) throw const FileSystemException('图片下载未返回结果');
    final path = response['path'] as String?;
    Stream<List<int>> content() async* {
      if (path == null) return;
      final file = File(path);
      try {
        yield* file.openRead();
      } finally {
        if (await file.exists()) await file.delete();
      }
    }

    return HttpGetResponse(
      http.StreamedResponse(
        content(),
        response['statusCode'] as int,
        contentLength: response['length'] as int? ?? 0,
        headers: (response['headers'] as Map).map(
          (key, value) => MapEntry('$key'.toLowerCase(), '$value'),
        ),
      ),
    );
  }
}
