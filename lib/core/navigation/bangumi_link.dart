import 'package:flutter/foundation.dart';

@immutable
class ComposeLinkTarget {
  const ComposeLinkTarget(this.kind, this.key, this.uri);
  final String kind, key;
  final Uri uri;
}

abstract final class BangumiLinkParser {
  static const hosts = {'bgm.tv', 'bangumi.tv', 'chii.in'};
  static ComposeLinkTarget? parse(String text) {
    if (text.length > 8192) return null;
    final candidate = RegExp(
      r'https?://[^\s<>"\[\]]+',
    ).firstMatch(text)?.group(0);
    if (candidate == null) return null;
    final uri = Uri.tryParse(
      candidate.replaceFirst(RegExp(r'[。。，，！!）)]+$'), ''),
    );
    if (uri == null ||
        !hosts.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.port != (uri.scheme == 'http' ? 80 : 443)) {
      return null;
    }
    try {
      final p = uri.pathSegments;
      if (p.length == 2 &&
          p[0] == 'user' &&
          RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(p[1])) {
        return ComposeLinkTarget(
          'user',
          p[1],
          uri.replace(scheme: 'https', port: 443),
        );
      }
      if (p.length == 2 &&
          const {'subject', 'ep', 'person', 'character'}.contains(p[0]) &&
          int.tryParse(p[1]) != null &&
          RegExp(r'^[1-9]\d*$').hasMatch(p[1])) {
        return ComposeLinkTarget(
          p[0],
          p[1],
          uri.replace(scheme: 'https', port: 443),
        );
      }
      if (p.length == 3 &&
          const {'group', 'subject'}.contains(p[0]) &&
          p[1] == 'topic' &&
          int.tryParse(p[2]) != null &&
          RegExp(r'^[1-9]\d*$').hasMatch(p[2])) {
        return ComposeLinkTarget(
          '${p[0]}Topic',
          p[2],
          uri.replace(scheme: 'https', port: 443),
        );
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
