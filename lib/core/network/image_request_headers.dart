/// 每次重定向重建匿名标头；豆瓣仅接收固定公开来源，不接收用户传入的来源。
Map<String, String> imageRequestHeaders(
  Uri uri,
  Map<String, String>? incoming,
) {
  final headers = <String, String>{};
  for (final entry in (incoming ?? <String, String>{}).entries) {
    if (const {
      'if-none-match',
      'if-modified-since',
      'accept',
    }.contains(entry.key.toLowerCase())) {
      headers[entry.key] = entry.value;
    }
  }
  final host = uri.host.toLowerCase();
  if (uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      (host == 'doubanio.com' || host.endsWith('.doubanio.com'))) {
    headers['Referer'] = 'https://m.douban.com/';
    headers['User-Agent'] = 'Mozilla/5.0';
  }
  return headers;
}
