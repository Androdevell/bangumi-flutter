import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../app_identity.dart';
import 'public_address.dart';
import 'tls_connection.dart';
import 'bounded_response.dart';

/// 仅本站域名使用有界 DoH；通过已校验 IP 建连，TLS 仍使用 URL 域名。
class BangumiDirectDns {
  static const hosts = {
    'bgm.tv',
    'next.bgm.tv',
    'api.bgm.tv',
    'lain.bgm.tv',
    'bangumi.tv',
    'chii.in',
  };
  final _cache =
      <String, ({List<InternetAddress> addresses, DateTime expiry})>{};
  final _pending = <String, Future<List<InternetAddress>>>{};
  Future<List<InternetAddress>> lookup(String host) {
    if (!hosts.contains(host)) {
      return InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
    }
    final cached = _cache[host];
    if (cached != null && cached.expiry.isAfter(DateTime.now())) {
      return Future.value(cached.addresses);
    }
    return _pending.putIfAbsent(
      host,
      () => _lookup(host).whenComplete(() {
        _pending.remove(host);
      }),
    );
  }

  Future<List<InternetAddress>> _lookup(String host) async {
    final clients = <IOClient>[];
    final winner = Completer<({List<InternetAddress> addresses, int ttl})>();
    var remaining = 2;
    Future<void> query(String resolver, String address, String path) async {
      final sockets =
          HttpClient()
            ..findProxy = ((_) => 'DIRECT')
            ..connectionTimeout = const Duration(seconds: 2);
      sockets.connectionFactory =
          (uri, _, __) async => authenticateConnection(
            uri,
            await Socket.startConnect(InternetAddress(address), uri.port),
          );
      final client = IOClient(sockets);
      clients.add(client);
      try {
        final stream = await client.send(
          http.Request(
              'GET',
              Uri.https(resolver, path, {'name': host, 'type': 'A'}),
            )
            ..followRedirects = false
            ..headers['accept'] = 'application/dns-json',
        );
        final response = await readBoundedResponse(
          stream,
          maxBytes: 8192,
          timeout: const Duration(seconds: 2),
        );
        if (response.statusCode != 200) return;
        final data = jsonDecode(response.body);
        if (data is! Map ||
            data['Status'] != 0 ||
            data['Question'] is! List ||
            !(data['Question'] as List).any(
              (q) =>
                  q is Map &&
                  '${q['name']}'.replaceFirst(RegExp(r'\.$'), '') == host &&
                  q['type'] == 1,
            )) {
          return;
        }
        final values = <InternetAddress>[];
        var ttl = 300;
        for (final a
            in data['Answer'] is List ? data['Answer'] as List : const []) {
          if (a is! Map || a['type'] != 1) continue;
          final ip = InternetAddress.tryParse('${a['data']}');
          if (ip != null && isPublicAddress(ip)) {
            values.add(ip);
            if (a['TTL'] is int) ttl = (a['TTL'] as int).clamp(1, ttl);
          }
        }
        if (values.isNotEmpty && !winner.isCompleted) {
          winner.complete((addresses: values, ttl: ttl));
        }
      } catch (_) {
        /* 主备竞争结束统一给出解析失败，不泄露请求。 */
      } finally {
        if (--remaining == 0 && !winner.isCompleted) {
          winner.completeError(const SocketException('Secure DNS unavailable'));
        }
      }
    }

    unawaited(query('dns.google', '8.8.8.8', '/resolve'));
    unawaited(query('cloudflare-dns.com', '1.1.1.1', '/dns-query'));
    try {
      final result = await winner.future.timeout(
        const Duration(milliseconds: 2300),
      );
      _cache[host] = (
        addresses: result.addresses,
        expiry: DateTime.now().add(Duration(seconds: result.ttl)),
      );
      return result.addresses;
    } catch (_) {
      // 与 Android 相同的短期应急路由；证书仍必须匹配原域名，30 秒后重新解析。
      final ips = switch (host) {
        'bangumi.tv' => ['178.79.181.137'],
        'chii.in' => ['104.21.93.3', '172.67.201.187'],
        _ => ['104.26.8.23', '104.26.9.23', '172.67.73.67'],
      };
      final values = ips.map(InternetAddress.new).toList();
      _cache[host] = (
        addresses: values,
        expiry: DateTime.now().add(const Duration(seconds: 30)),
      );
      return values;
    } finally {
      for (final c in clients) {
        c.close();
      }
    }
  }
}

final _sharedDirectDns = BangumiDirectDns();
Future<List<InternetAddress>> resolveWindowsDirectHost(String host) =>
    _sharedDirectDns.lookup(host);

http.Client createWindowsDirectClient() {
  final dns = _sharedDirectDns;
  final sockets =
      HttpClient()
        ..userAgent = browserUserAgent
        ..findProxy = ((_) => 'DIRECT')
        ..connectionTimeout = const Duration(seconds: 8);
  sockets.connectionFactory = (uri, proxy, port) async {
    if (proxy != null) {
      throw const SocketException('Proxy not allowed in direct mode');
    }
    final addresses = await dns.lookup(uri.host);
    if (addresses.isEmpty || addresses.any((a) => !isPublicAddress(a))) {
      throw const SocketException('Unsafe destination');
    }
    if (uri.scheme == 'https' && BangumiDirectDns.hosts.contains(uri.host)) {
      Object? lastError;
      for (final address in addresses.take(3)) {
        ConnectionTask<Socket>? task;
        try {
          task = await directTlsConnection([address], uri.port);
          final secure = await authenticateConnection(
            uri,
            task,
          ).socket.timeout(const Duration(seconds: 4));
          return ConnectionTask.fromSocket(
            Future.value(secure),
            secure.destroy,
          );
        } on Object catch (error) {
          task?.cancel();
          lastError = error;
        }
      }
      throw lastError ?? const SocketException('Direct TLS unavailable');
    }
    return authenticateConnection(
      uri,
      await Socket.startConnect(addresses.first, uri.port),
    );
  };
  return IOClient(sockets);
}

/// 一次性、仅回环的加密字节转发；TLS 和证书验证仍由 HttpClient 使用原域名完成。
/// 不解析 HTTP、不接受目标参数，也不向其它本地连接提供代理服务。
Future<ConnectionTask<Socket>> directTlsConnection(
  List<InternetAddress> addresses,
  int port,
) async {
  Socket? remote;
  for (final address in addresses) {
    try {
      remote = await Socket.connect(
        address,
        port,
        timeout: const Duration(seconds: 3),
      );
      break;
    } on SocketException {
      /* 同一已验证域名的下一个公网地址。 */
    }
  }
  if (remote == null) throw const SocketException('Direct connection failed');
  final upstream = remote;
  ServerSocket? listener;
  try {
    listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final server = listener;
    final localFuture = Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
    );
    final accepted = Completer<Socket>();
    final subscription = server.listen((socket) async {
      final local = await localFuture;
      if (socket.remotePort != local.port || accepted.isCompleted) {
        socket.destroy();
      } else {
        accepted.complete(socket);
      }
    });
    final local = await localFuture;
    final bridge = await accepted.future.timeout(const Duration(seconds: 2));
    await subscription.cancel();
    await server.close();
    final expiry = Timer(const Duration(minutes: 2), () {
      bridge.destroy();
      upstream.destroy();
    });
    void close() {
      expiry.cancel();
      bridge.destroy();
      upstream.destroy();
    }

    unawaited(
      upstream
          .addStream(fragmentClientHello(bridge))
          .then((_) => close(), onError: (Object _) => close()),
    );
    unawaited(
      bridge
          .addStream(upstream)
          .then((_) => close(), onError: (Object _) => close()),
    );
    return ConnectionTask.fromSocket(Future.value(local), () {
      local.destroy();
      close();
    });
  } on Object {
    upstream.destroy();
    await listener?.close();
    rethrow;
  }
}

/// 仅拆分第一个 ClientHello 的 TLS record；握手内容、SNI 和认证信息不变。
Stream<List<int>> fragmentClientHello(Stream<List<int>> source) async* {
  final buffer = <int>[];
  var handled = false;
  await for (final chunk in source) {
    if (handled) {
      yield chunk;
      continue;
    }
    buffer.addAll(chunk);
    if (buffer.length < 5) continue;
    final size = 5 + (buffer[3] << 8) + buffer[4];
    if (buffer[0] != 22 || size > 18437) {
      handled = true;
      yield List<int>.of(buffer);
      buffer.clear();
      continue;
    }
    if (buffer.length < size) continue;
    final split = clientHelloSniSplit(buffer.sublist(0, size));
    if (split != null) {
      // 与 Android 兼容布局一致；只改 record 包装，不改 ClientHello 内容和认证。
      for (final (start, end) in [(5, split), (split, size)]) {
        final middle = start + (end - start) ~/ 2;
        for (final (a, b) in [(start, middle), (middle, end)]) {
          final length = b - a;
          if (length > 0) {
            yield [
              22,
              3,
              4,
              length >> 8,
              length & 255,
              ...buffer.sublist(a, b),
            ];
          }
        }
      }
    } else {
      yield buffer.sublist(0, size);
    }
    if (buffer.length > size) yield buffer.sublist(size);
    buffer.clear();
    handled = true;
  }
  if (buffer.isNotEmpty) yield buffer;
}

int? clientHelloSniSplit(List<int> record) {
  try {
    if (record.length < 43 || record[0] != 22 || record[5] != 1) return null;
    int u16(int p) => (record[p] << 8) | record[p + 1];
    var p = 43;
    p += 1 + record[p];
    p += 2 + u16(p);
    p += 1 + record[p];
    final end = p + 2 + u16(p);
    p += 2;
    if (end > record.length) return null;
    while (p + 4 <= end) {
      final type = u16(p), length = u16(p + 2);
      final data = p + 4;
      if (data + length > end) return null;
      if (type == 0 && length >= 5 && record[data + 2] == 0) {
        final start = data + 5, nameEnd = data + 5 + u16(data + 3);
        if (nameEnd > data + length) return null;
        for (var i = nameEnd - 1; i > start; i--) {
          if (record[i] == 46) return i;
        }
        return null;
      }
      p = data + length;
    }
  } on RangeError {
    return null;
  }
  return null;
}
