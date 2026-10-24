import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../app_identity.dart';

/// WinHTTP 仅用于后台发现代理；实际 IO/取消由 Dart socket 管理，避免原生回调缓冲竞争。
class WindowsSystemClient extends http.BaseClient {
  WindowsSystemClient({Future<String> Function(Uri)? resolve})
    : _resolve =
          resolve ?? ((uri) => Isolate.run(() => _systemProxy(uri.toString())));
  final Future<String> Function(Uri) _resolve;
  final _routes = <String, Future<String>>{};
  final _clients = <String, IOClient>{};
  bool _closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Client closed');
    final key =
        '${request.url.scheme}://${request.url.host}:${request.url.port}';
    final proxy = await _routes.putIfAbsent(key, () async {
      try {
        return await _resolve(request.url).timeout(const Duration(seconds: 8));
      } on Object {
        _routes.removeWhere((cached, _) => cached == key);
        rethrow;
      }
    });
    if (_closed) throw http.ClientException('Client closed');
    final client = _clients.putIfAbsent(
      proxy,
      () => IOClient(
        HttpClient()
          ..userAgent = browserUserAgent
          ..connectionTimeout = const Duration(seconds: 12)
          ..findProxy = (_) => proxy,
      ),
    );
    return client.send(request);
  }

  @override
  void close() {
    _closed = true;
    for (final c in _clients.values) {
      c.close();
    }
    _clients.clear();
    _routes.clear();
  }
}

String windowsProxyDirective(Uri uri, String proxy, String bypass) {
  for (final rule in bypass
      .split(RegExp(r'[;,]'))
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)) {
    if (rule == '<local>' && !uri.host.contains('.')) return 'DIRECT';
    final pattern =
        '^${RegExp.escape(rule).replaceAll(r'\*', '.*')}'
        r'$';
    if (RegExp(pattern, caseSensitive: false).hasMatch(uri.host)) {
      return 'DIRECT';
    }
  }
  final entries = proxy
      .split(';')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty);
  var selected = '';
  for (final entry in entries) {
    final pair = entry.split('=');
    if (pair.length == 1) {
      selected = pair.first;
      break;
    }
    if (pair.first.toLowerCase() == uri.scheme) {
      selected = pair.last;
      break;
    }
  }
  if (selected.isEmpty) return 'DIRECT';
  final parsed = Uri.tryParse(
    selected.contains('://') ? selected : 'http://$selected',
  );
  if (parsed == null ||
      !{'http', 'https'}.contains(parsed.scheme) ||
      parsed.host.isEmpty ||
      parsed.userInfo.isNotEmpty ||
      (parsed.path.isNotEmpty && parsed.path != '/')) {
    throw const SocketException('Unsupported system proxy');
  }
  return 'PROXY ${parsed.host.contains(':') ? '[${parsed.host}]' : parsed.host}:${parsed.port}';
}

final class _IeConfig extends Struct {
  @Int32()
  external int autoDetect;
  external Pointer<Utf16> autoUrl;
  external Pointer<Utf16> proxy;
  external Pointer<Utf16> bypass;
}

final class _ProxyInfo extends Struct {
  @Uint32()
  external int access;
  external Pointer<Utf16> proxy;
  external Pointer<Utf16> bypass;
}

final class _AutoOptions extends Struct {
  @Uint32()
  external int flags;
  @Uint32()
  external int detect;
  external Pointer<Utf16> url;
  external Pointer<Void> reserved;
  @Uint32()
  external int reservedFlags;
  @Int32()
  external int autoLogon;
}

String _systemProxy(String address) {
  final lib = DynamicLibrary.open('winhttp.dll');
  final kernel = DynamicLibrary.open('kernel32.dll');
  final free = kernel.lookupFunction<
    Pointer<Void> Function(Pointer<Void>),
    Pointer<Void> Function(Pointer<Void>)
  >('GlobalFree');
  final read = lib.lookupFunction<
    Int32 Function(Pointer<_IeConfig>),
    int Function(Pointer<_IeConfig>)
  >('WinHttpGetIEProxyConfigForCurrentUser');
  final config = calloc<_IeConfig>();
  String str(Pointer<Utf16> p) => p == nullptr ? '' : p.toDartString();
  void release(Pointer<Utf16> p) {
    if (p != nullptr) free(p.cast());
  }

  try {
    if (read(config) == 0) {
      return HttpClient.findProxyFromEnvironment(Uri.parse(address));
    }
    final manual = str(config.ref.proxy);
    final bypass = str(config.ref.bypass);
    if (manual.isNotEmpty) {
      return windowsProxyDirective(Uri.parse(address), manual, bypass);
    }
    if (config.ref.autoUrl == nullptr && config.ref.autoDetect == 0) {
      return 'DIRECT';
    }
    final open = lib.lookupFunction<
      IntPtr Function(
        Pointer<Utf16>,
        Uint32,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
      ),
      int Function(Pointer<Utf16>, int, Pointer<Utf16>, Pointer<Utf16>, int)
    >('WinHttpOpen');
    final close = lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'WinHttpCloseHandle',
    );
    final timeout = lib.lookupFunction<
      Int32 Function(IntPtr, Int32, Int32, Int32, Int32),
      int Function(int, int, int, int, int)
    >('WinHttpSetTimeouts');
    final resolve = lib.lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Utf16>,
        Pointer<_AutoOptions>,
        Pointer<_ProxyInfo>,
      ),
      int Function(
        int,
        Pointer<Utf16>,
        Pointer<_AutoOptions>,
        Pointer<_ProxyInfo>,
      )
    >('WinHttpGetProxyForUrl');
    final agent = browserUserAgent.toNativeUtf16();
    final url = address.toNativeUtf16();
    final options = calloc<_AutoOptions>();
    final result = calloc<_ProxyInfo>();
    final session = open(agent, 1, nullptr, nullptr, 0);
    try {
      if (session == 0) {
        throw const SocketException('Proxy discovery unavailable');
      }
      timeout(session, 2000, 2000, 2000, 2000);
      options.ref
        ..flags = config.ref.autoUrl != nullptr ? 2 : 1
        ..detect = config.ref.autoUrl != nullptr ? 0 : 3
        ..url = config.ref.autoUrl
        ..autoLogon = 0;
      if (resolve(session, url, options, result) == 0) {
        // WPAD 无配置时直连；显式 PAC 失败不能默默泄漏到直连。
        if (config.ref.autoUrl != nullptr) {
          throw const SocketException('PAC discovery failed');
        }
        return 'DIRECT';
      }
      return windowsProxyDirective(
        Uri.parse(address),
        str(result.ref.proxy),
        str(result.ref.bypass),
      );
    } finally {
      if (session != 0) close(session);
      release(result.ref.proxy);
      release(result.ref.bypass);
      calloc.free(result);
      calloc.free(options);
      calloc.free(agent);
      calloc.free(url);
    }
  } finally {
    release(config.ref.autoUrl);
    release(config.ref.proxy);
    release(config.ref.bypass);
    calloc.free(config);
  }
}
