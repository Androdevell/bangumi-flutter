import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 可重建的数据集中存放；凭据、设置和用户导出文件不进入该目录。
abstract final class CacheStorage {
  static const namespace = 'bangumi-cache-v1';
  static const imageKey = '$namespace/images';
  static Future<Directory> root() async =>
      Directory('${(await getTemporaryDirectory()).path}/$namespace');
  static Future<Directory> images() async =>
      Directory('${(await root()).path}/images');
  static Future<Directory> publicData() async =>
      Directory('${(await root()).path}/public');
  static Future<Directory> transfers() async =>
      Directory('${(await root()).path}/transfers');
  static Future<Directory> legacyImages() async =>
      Directory('${(await getTemporaryDirectory()).path}/bangumiImageCacheV2');
}
