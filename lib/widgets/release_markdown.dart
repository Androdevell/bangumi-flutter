import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

/// 发行说明只渲染 Markdown；图片不联网，链接仅接受 HTTP(S)。
class ReleaseMarkdown extends StatelessWidget {
  const ReleaseMarkdown(this.data, {super.key, this.openLink});
  final String data;
  final Future<void> Function(Uri)? openLink;
  static Uri? safeLink(String? href) {
    final uri = Uri.tryParse(href ?? '');
    return uri != null &&
            const {'http', 'https'}.contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }

  @override
  Widget build(BuildContext context) => MarkdownBody(
    data: data,
    selectable: true,
    styleSheet: MarkdownStyleSheet.fromTheme(
      Theme.of(context),
    ).copyWith(tableColumnWidth: const IntrinsicColumnWidth()),
    sizedImageBuilder: (config) => Text(config.alt ?? ''),
    onTapLink: (_, href, _) async {
      final uri = safeLink(href);
      if (uri == null) return;
      try {
        if (openLink != null) {
          await openLink!(uri);
        } else {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } on Object {
        /* 外部浏览器失败不影响说明阅读。 */
      }
    },
  );
}
