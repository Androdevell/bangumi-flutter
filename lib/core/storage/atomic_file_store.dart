import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:ffi/ffi.dart';

/// 同目录临时文件、进程内顺序及跨进程文件锁保护加密记录提交。
class AtomicFileStore {
  AtomicFileStore({this.beforeCommit});
  final Future<void> Function()? beforeCommit;
  static final _pending = <String, Future<void>>{};
  static final _random = Random.secure();

  Future<T> locked<T>(File file, Future<T> Function() action) async {
    final key = file.absolute.path;
    final previous = _pending[key] ?? Future<void>.value();
    final done = Completer<void>();
    _pending[key] = done.future;
    await previous;
    RandomAccessFile? lock;
    try {
      lock = await File('$key.lock').open(mode: FileMode.append);
      await lock.lock(FileLock.blockingExclusive);
      return await action();
    } finally {
      try {
        if (lock != null) {
          await lock.unlock();
          await lock.close();
        }
      } finally {
        done.complete();
        if (identical(_pending[key], done.future)) {
          // ignore: unawaited_futures
          _pending.remove(key);
        }
      }
    }
  }

  Future<void> write(File file, String value) => locked(file, () async {
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.${_random.nextInt(1 << 32)}.tmp',
    );
    try {
      await temporary.writeAsString(value, flush: true);
      await beforeCommit?.call();
      if (Platform.isWindows) {
        final kernel = DynamicLibrary.open('kernel32.dll');
        final move = kernel.lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
          int Function(Pointer<Utf16>, Pointer<Utf16>, int)
        >('MoveFileExW');
        final from = temporary.absolute.path.toNativeUtf16();
        final to = file.absolute.path.toNativeUtf16();
        try {
          // 同卷替换；不先删除旧记录，不允许跨卷复制退化。
          if (move(from, to, 0x1 | 0x8) == 0) {
            throw const FileSystemException(
              'Atomic secure record replacement failed',
            );
          }
        } finally {
          calloc.free(from);
          calloc.free(to);
        }
      } else {
        await temporary.rename(file.path);
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  });
}
