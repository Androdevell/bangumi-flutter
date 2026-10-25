import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import '../app_identity.dart';

enum ImageEvent {
  request,
  ready,
  failed,
  cooldown,
  transferCreated,
  cleanupStarted,
  cleanupFinished,
  cleanupDeferred,
  cleanupRepeated,
}

/// 有界的本地图片诊断；只接受阶段和整数，不接收 URL、错误正文或凭据。
class ImageDiagnostics {
  ImageDiagnostics({this.enabled = false});
  static final instance = ImageDiagnostics(
    enabled: const bool.fromEnvironment('IMAGE_DIAGNOSTICS'),
  );
  final bool enabled;
  final _events = Queue<Map<String, Object>>();
  final _pending = Queue<String>();
  final _counts = <ImageEvent, int>{};
  int _next = 0;
  int _sequence = 0;
  File? _file;
  Future<void>? _writing;
  int _written = 0;
  int get nextRequest => ++_next;
  Map<String, Object> get snapshot => {
    'version': appVersion,
    'counts': {for (final e in _counts.entries) e.key.name: e.value},
    'events': _events.toList(growable: false),
  };

  void record(ImageEvent event, int request, {int category = 0}) {
    if (!enabled) return;
    _counts[event] = (_counts[event] ?? 0) + 1;
    final entry = <String, Object>{
      'seq': ++_sequence,
      'request': request,
      'event': event.name,
      'category': category,
    };
    _events.add(entry);
    if (_events.length > 128) _events.removeFirst();
    if (_file != null) {
      _pending.add('${jsonEncode(entry)}\n');
      if (_pending.length > 128) _pending.removeFirst();
      _writing ??= _write().whenComplete(() => _writing = null);
    }
  }

  /// 仅显式诊断构建启用；写入失败不影响图片和应用启动。
  Future<void> open(File file) async {
    if (!enabled) return;
    try {
      await file.parent.create(recursive: true);
      if (await file.exists()) {
        final previous = File('${file.path}.previous');
        if (await previous.exists()) await previous.delete();
        await file.rename(previous.path);
      }
      await file.writeAsString(
        '${jsonEncode({'version': appVersion})}\n',
        flush: true,
      );
      _file = file;
    } on FileSystemException {
      _file = null;
    }
  }

  Future<void> _write() async {
    try {
      while (_pending.isNotEmpty) {
        final batch = StringBuffer();
        while (_pending.isNotEmpty) {
          batch.write(_pending.removeFirst());
        }
        final text = batch.toString();
        if (_written + text.length > 128 * 1024) {
          await _file!.writeAsString('${jsonEncode(snapshot)}\n', flush: true);
          _written = 0;
        }
        await _file!.writeAsString(text, mode: FileMode.append, flush: true);
        _written += text.length;
      }
    } on FileSystemException {
      _pending.clear();
      _file = null;
    }
  }

  Future<void> flush() async => await _writing;
}
