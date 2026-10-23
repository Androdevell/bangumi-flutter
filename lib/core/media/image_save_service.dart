import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import '../network/app_image_cache.dart';

/// 保存缓存中的原始字节，不截屏、不重新编码，保留 GIF/WebP 动画。
class ImageSaveService {
  ImageSaveService({
    Future<File> Function(String)? fetch,
    Future<bool> Function(File, String, String)? export,
  }) : _fetch = fetch ?? AppImageCache.manager.getSingleFile,
       _export = export;
  final Future<File> Function(String) _fetch;
  final Future<bool> Function(File, String, String)? _export;
  static const channel = MethodChannel('com.bgm.irena/media');

  static ({String extension, String mime}) identify(List<int> bytes) {
    bool at(int offset, List<int> signature) =>
        bytes.length >= offset + signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[offset + i] == signature[i],
        ).every((value) => value);
    if (at(0, [137, 80, 78, 71, 13, 10, 26, 10])) {
      return (extension: 'png', mime: 'image/png');
    }
    if (at(0, [255, 216, 255])) return (extension: 'jpg', mime: 'image/jpeg');
    if (at(0, [71, 73, 70, 56, 55, 97]) || at(0, [71, 73, 70, 56, 57, 97])) {
      return (extension: 'gif', mime: 'image/gif');
    }
    if (at(0, [82, 73, 70, 70]) && at(8, [87, 69, 66, 80])) {
      return (extension: 'webp', mime: 'image/webp');
    }
    if (at(0, [66, 77])) return (extension: 'bmp', mime: 'image/bmp');
    if (at(4, [102, 116, 121, 112]) &&
        (at(8, [97, 118, 105, 102]) || at(8, [97, 118, 105, 115]))) {
      return (extension: 'avif', mime: 'image/avif');
    }
    throw const FormatException('Unsupported image');
  }

  /// 权限在下载完成和文件选择结束后再次检查，关闭第三方图片后不继续导出。
  Future<bool> save(String url, {required bool Function() allowed}) async {
    if (!allowed()) return false;
    final file = await _fetch(url);
    if (!allowed()) return false;
    final length = await file.length();
    if (length == 0 || length > 20 * 1024 * 1024) {
      throw const FormatException('Image exceeds size limit');
    }
    final input = await file.open();
    late final ({String extension, String mime}) type;
    try {
      type = identify(await input.read(32));
    } finally {
      await input.close();
    }
    final name =
        'bangumi-${DateTime.now().millisecondsSinceEpoch}.${type.extension}';
    if (!allowed()) return false;
    return _export?.call(file, name, type.mime) ??
        _exportOriginal(file, name, type.mime, allowed);
  }

  static Future<bool> _exportOriginal(
    File file,
    String name,
    String mime,
    bool Function() allowed,
  ) async {
    if (Platform.isAndroid) {
      return await channel.invokeMethod<bool>('saveImage', {
            'path': file.path,
            'name': name,
            'mime': mime,
          }) ??
          false;
    }
    final destination = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        XTypeGroup(label: 'Image', extensions: [name.split('.').last]),
      ],
    );
    if (destination == null || !allowed()) return false;
    await XFile(file.path, mimeType: mime).saveTo(destination.path);
    return true;
  }
}
