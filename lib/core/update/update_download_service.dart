import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../network/platform_http_client.dart';
import 'app_update_service.dart';

class UpdateDownloadService extends ChangeNotifier {
  UpdateDownloadService({
    http.Client Function()? clientFactory,
    Future<Directory> Function()? directoryProvider,
  }) : _clientFactory = clientFactory ?? createPlatformHttpClient,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;
  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _directoryProvider;
  static const _native = MethodChannel('com.bgm.irena/update');
  http.Client? _client;
  bool busy = false, cancelled = false, verified = false, _closed = false;
  int received = 0, total = 0;
  String? error;
  File? file;
  String? _requestId;
  String? _expectedDigest;
  final Stopwatch _watch = Stopwatch();
  double get bytesPerSecond =>
      _watch.elapsedMilliseconds == 0
          ? 0
          : received * 1000 / _watch.elapsedMilliseconds;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> download(ComposeUpdateAsset asset) async {
    if (busy || _closed) return;
    file = null;
    verified = false;
    _expectedDigest = null;
    if (asset.digest == null ||
        !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(asset.digest!)) {
      error = 'downloadNoDigest';
      _notify();
      return;
    }
    if (!isTrustedUpdateUri(asset.url) ||
        !RegExp(
          r'^bangumi-[0-9.]+-(arm64-v8a\.apk|windows-x64\.zip)$',
        ).hasMatch(asset.name)) {
      error = 'downloadFailed';
      _notify();
      return;
    }
    busy = true;
    cancelled = false;
    verified = false;
    received = 0;
    total = asset.size;
    error = null;
    file = null;
    _expectedDigest = null;
    _watch
      ..reset()
      ..start();
    _notify();
    File? part;
    try {
      if (Platform.isAndroid) {
        final id =
            _requestId = DateTime.now().microsecondsSinceEpoch.toString();
        _native.setMethodCallHandler((call) async {
          if (call.method != 'progress' ||
              _closed ||
              cancelled ||
              call.arguments['id'] != id) {
            return;
          }
          received = (call.arguments['received'] as num).toInt();
          _notify();
        });
        final path = await _native.invokeMethod<String>('download', {
          'url': asset.url.toString(),
          'name': asset.name,
          'id': id,
          'size': asset.size,
        });
        if (path == null) throw const FormatException();
        part = File(path);
      } else {
        final root = await _directoryProvider();
        final directory = Directory('${root.path}/updates');
        await directory.create(recursive: true);
        part = File(
          '${directory.path}/${DateTime.now().microsecondsSinceEpoch}-${asset.name}.part',
        );
        final client = _client = _clientFactory();
        var uri = asset.url;
        http.StreamedResponse? response;
        for (var redirect = 0; redirect <= 5; redirect++) {
          if (!isTrustedUpdateUri(uri) || cancelled) {
            throw const FormatException();
          }
          final result = await client
              .send(http.Request('GET', uri)..followRedirects = false)
              .timeout(const Duration(seconds: 30));
          if ({301, 302, 303, 307, 308}.contains(result.statusCode)) {
            final next = result.headers['location'];
            await result.stream.drain<void>().timeout(
              const Duration(seconds: 10),
            );
            if (next == null) throw const FormatException();
            uri = uri.resolve(next);
            continue;
          }
          response = result;
          break;
        }
        if (response == null || response.statusCode != 200) {
          throw const FormatException();
        }
        if (response.contentLength != null &&
            response.contentLength != asset.size) {
          throw const FormatException('downloadIntegrity');
        }
        final sink = part.openWrite();
        var notifiedAt = 0;
        try {
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 30),
          )) {
            if (cancelled || _closed) throw StateError('cancelled');
            received += chunk.length;
            if (received > asset.size || received > 512 * 1024 * 1024) {
              throw const FormatException('downloadIntegrity');
            }
            sink.add(chunk);
            if (_watch.elapsedMilliseconds - notifiedAt > 100) {
              await sink.flush();
              notifiedAt = _watch.elapsedMilliseconds;
              _notify();
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      }
      if (cancelled || _closed) throw StateError('cancelled');
      if (await part.length() != asset.size) {
        throw const FormatException('downloadIntegrity');
      }
      if (asset.digest != null) {
        final hash = await compute(_fileDigest, part.path);
        if ('sha256:$hash' != asset.digest!.toLowerCase()) {
          throw const FormatException('downloadIntegrity');
        }
        verified = true;
      }
      if (cancelled || _closed) throw StateError('cancelled');
      file = await part.rename(part.path.replaceFirst(RegExp(r'\.part$'), ''));
      _expectedDigest = asset.digest;
      try {
        await pruneUpdateFiles(file!.parent, keep: file!.path);
      } on FileSystemException {
        // 缓存回收失败不能把已完成且已验证的下载变成失败。
      }
      received = asset.size;
    } on Object catch (failure) {
      try {
        if (part != null && await part.exists()) await part.delete();
      } on FileSystemException {
        /* 保留失败文件路径仅供下次人工清理。 */
      }
      error =
          cancelled
              ? 'downloadCancelled'
              : failure is FormatException &&
                  failure.message == 'downloadIntegrity'
              ? 'downloadIntegrity'
              : 'downloadFailed';
    } finally {
      _watch.stop();
      _client?.close();
      _client = null;
      _requestId = null;
      if (Platform.isAndroid) _native.setMethodCallHandler(null);
      busy = false;
      _notify();
    }
  }

  Future<void> cancel() async {
    cancelled = true;
    _client?.close();
    if (Platform.isAndroid && _requestId != null) {
      try {
        await _native.invokeMethod<void>('cancel', {'id': _requestId});
      } on Object {
        /* 原调用仍会超时结束。 */
      }
    }
  }

  Future<bool> installAndroid() async {
    if (file == null || !verified || _expectedDigest == null || busy) {
      return false;
    }
    try {
      return await _native.invokeMethod<bool>('install', {
            'path': file!.path,
            'sha256': _expectedDigest!.substring('sha256:'.length),
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(cancel());
    super.dispose();
  }
}

Future<String> _fileDigest(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

/// 仅清理本下载器命名的旧包和过期分片；保留当前包及最近一个已完成包。
Future<void> pruneUpdateFiles(
  Directory directory, {
  required String keep,
}) async {
  final complete = <File>[];
  final retained = File(keep).absolute.uri.normalizePath();
  final cutoff = DateTime.now().subtract(const Duration(days: 1));
  await for (final entry in directory.list(followLinks: false)) {
    if (entry is! File || entry.absolute.uri.normalizePath() == retained) {
      continue;
    }
    final name = entry.uri.pathSegments.last;
    if (!RegExp(
      r'^\d+-bangumi-[0-9.]+-(arm64-v8a\.apk|windows-x64\.zip)(\.part)?$',
    ).hasMatch(name)) {
      continue;
    }
    try {
      if (name.endsWith('.part')) {
        if ((await entry.lastModified()).isBefore(cutoff)) await entry.delete();
      } else {
        complete.add(entry);
      }
    } on FileSystemException {
      /* 正在占用的文件不强制删除。 */
    }
  }
  final dates = <String, DateTime>{};
  for (final file in complete) {
    try {
      dates[file.path] = await file.lastModified();
    } on FileSystemException {
      // 文件可能已被其他清理任务移除。
    }
  }
  complete.sort(
    (a, b) => (dates[b.path] ?? DateTime(1970)).compareTo(
      dates[a.path] ?? DateTime(1970),
    ),
  );
  for (final file in complete.skip(1)) {
    try {
      await file.delete();
    } on FileSystemException {
      // 文件仍被系统安装器或用户占用时留待下次。
    }
  }
}
