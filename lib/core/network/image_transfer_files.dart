import 'dart:io';
import '../diagnostics/image_diagnostics.dart';
import '../cache/cache_storage.dart';

/// 创建请求独占的临时文件；在首次创建前完成一次旧分片清理。
class ImageTransferFiles {
  ImageTransferFiles({Directory? directory}) : _directory = directory;
  final Directory? _directory;
  late Directory _root;
  Future<void>? _initializing;

  Future<ImageTransferFile> create({
    int request = 0,
    ImageDiagnostics? diagnostics,
  }) async {
    await (_initializing ??= _initialize());
    final folder = await _root.createTemp('transfer-');
    final file = File('${folder.path}/image.part');
    return ImageTransferFile._(
      file,
      request,
      diagnostics ?? ImageDiagnostics.instance,
    );
  }

  Future<void> _initialize() async {
    _root = _directory ?? await CacheStorage.transfers();
    await _root.create(recursive: true);
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
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
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

/// 一个下载独占其文件和释放状态；异常与流结束共用幂等释放操作。
class ImageTransferFile {
  ImageTransferFile._(this.file, this.request, this.diagnostics) {
    diagnostics.record(ImageEvent.transferCreated, request);
  }
  final File file;
  final int request;
  final ImageDiagnostics diagnostics;
  Future<void>? _releasing;

  Future<void> prepare(
    Stream<List<int>> source,
    Future<void> Function(File) validate,
  ) async {
    try {
      await _write(source);
      await validate(file);
    } catch (_) {
      await release();
      rethrow;
    }
  }

  Future<void> _write(Stream<List<int>> source) async {
    final sink = file.openWrite();
    Object? failure;
    StackTrace? trace;
    try {
      await sink.addStream(source);
    } catch (error, stack) {
      failure = error;
      trace = stack;
    }
    try {
      await sink.close();
    } catch (error, stack) {
      failure ??= error;
      trace ??= stack;
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
  }

  Stream<List<int>> read() async* {
    try {
      yield* file.openRead();
    } finally {
      await release();
    }
  }

  Future<void> release() {
    if (_releasing != null) {
      diagnostics.record(ImageEvent.cleanupRepeated, request);
    }
    return _releasing ??= _delete();
  }

  Future<void> _delete() async {
    diagnostics.record(ImageEvent.cleanupStarted, request);
    try {
      if (await file.exists()) await file.delete();
      await file.parent.delete();
      diagnostics.record(ImageEvent.cleanupFinished, request);
    } on FileSystemException {
      diagnostics.record(ImageEvent.cleanupDeferred, request);
      // 占用或中断留下的分片在下次启动按 TTL 再回收。
    }
  }
}
