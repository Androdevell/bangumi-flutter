import 'dart:io';

/// 临时图片文件的唯一所有者；只回收本工具目录中一天前的单个分片。
class ImageTransferFiles {
  ImageTransferFiles({Directory? directory})
    : _root =
          directory ??
          Directory('${Directory.systemTemp.path}/bangumi-image-transfers-v1');
  final Directory _root;
  final _active = <Uri>{};
  bool _swept = false;

  Future<File> create() async {
    await _root.create(recursive: true);
    if (!_swept) {
      _swept = true;
      await prune();
    }
    final folder = await _root.createTemp('transfer-');
    final file = File('${folder.path}/image.part');
    _active.add(file.absolute.uri.normalizePath());
    return file;
  }

  Future<void> release(File file) async {
    _active.remove(file.absolute.uri.normalizePath());
    try {
      if (await file.exists()) await file.delete();
      await file.parent.delete(); // 非递归；不删除意外出现的其他文件。
    } on FileSystemException {
      // 占用或中断留下的分片在下次启动按 TTL 再回收。
    }
  }

  Future<void> prune() async {
    if (!await _root.exists()) return;
    final root =
        Directory(
          await _root.resolveSymbolicLinks(),
        ).absolute.uri.normalizePath();
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    await for (final child in _root.list(followLinks: false)) {
      if (child is! Directory ||
          !child.uri.pathSegments
              .where((p) => p.isNotEmpty)
              .last
              .startsWith('transfer-')) {
        continue;
      }
      try {
        final resolved = Directory(await child.resolveSymbolicLinks());
        if (resolved.parent.absolute.uri.normalizePath() != root) continue;
        final file = File('${resolved.path}/image.part');
        if (_active.contains(file.absolute.uri.normalizePath()) ||
            await FileSystemEntity.type(file.path, followLinks: false) !=
                FileSystemEntityType.file ||
            !(await file.lastModified()).isBefore(cutoff)) {
          continue;
        }
        await file.delete();
        await resolved.delete();
      } on FileSystemException {
        // 不跟随链接，不递归，也不强制删除其他进程占用的文件。
      }
    }
  }
}
