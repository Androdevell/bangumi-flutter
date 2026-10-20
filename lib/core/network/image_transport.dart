import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../media/rich_image_policy.dart';
import '../app_identity.dart';
import 'image_request_headers.dart';

/// 未知图床在实际建连时解析并验证地址。可信固定图床保留系统代理兼容。
class ImageTransport extends http.BaseClient {
  ImageTransport(
    this.compatible, {
    Future<List<InternetAddress>> Function(String)? lookup,
  }) {
    final resolver = lookup ?? InternetAddress.lookup;
    final sockets =
        HttpClient()
          ..userAgent = browserUserAgent
          ..connectionTimeout = const Duration(seconds: 15)
          ..findProxy = (_) => 'DIRECT';
    sockets.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (!ImageUrlSafety.valid(uri) || proxyHost != null) {
        throw const HttpException('Unsafe image connection');
      }
      final addresses = await resolver(
        uri.host,
      ).timeout(const Duration(seconds: 10));
      if (addresses.isEmpty ||
          addresses.any((a) => !ImageUrlSafety.publicAddress(a))) {
        throw const HttpException('Private image connection');
      }
      // 直接传入地址，Socket 不会对域名进行第二次解析；TLS 仍使用原 URL 的主机名。
      return Socket.startConnect(addresses.first, uri.port);
    };
    pinned = IOClient(sockets);
  }
  final http.Client compatible;
  late final http.Client pinned;
  static bool compatibleHost(String host) =>
      RichImagePolicy.trustedHosts.contains(host) ||
      RegExp(r'^img[0-9]+\.doubanio\.com$').hasMatch(host) ||
      host == 'doubanio.com';
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!ImageUrlSafety.valid(request.url)) {
      throw const HttpException('Unsafe image connection');
    }
    final headers = imageRequestHeaders(request.url, request.headers);
    request.headers
      ..clear()
      ..addAll(headers);
    request.followRedirects = false;
    return (compatibleHost(request.url.host) ? compatible : pinned).send(
      request,
    );
  }

  @override
  void close() {
    pinned.close();
    compatible.close();
  }
}
