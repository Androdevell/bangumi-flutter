import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;

@immutable
class ComposeRichTextNode {
  ComposeRichTextNode(
    this.tag,
    this.value,
    Iterable<ComposeRichTextNode> children,
  ) : children = List.unmodifiable(children);
  final String tag;
  final String value;
  final List<ComposeRichTextNode> children;
}

@immutable
class ComposeRichTextDocument {
  ComposeRichTextDocument(Iterable<ComposeRichTextNode> nodes, this.truncated)
    : nodes = List.unmodifiable(nodes);
  final List<ComposeRichTextNode> nodes;
  final bool truncated;
}

class _Frame {
  _Frame(this.tag, this.value);
  final String tag;
  final String value;
  final List<Object> children = [];
  ComposeRichTextNode freeze() => ComposeRichTextNode(
    tag,
    value,
    children.map(
      (child) =>
          child is _Frame ? child.freeze() : child as ComposeRichTextNode,
    ),
  );
}

/// 有界栈解析；文本只解码实体，不将尖括号解释成 HTML。
abstract final class BangumiBbCode {
  static final _tokens = RegExp(
    r'\[(/?)(b|i|u|s|mask|size|color|quote|url|img|br)(?:=([^\]\r\n]*))?\s*/?\]|\((?:bgm(?:\d+|124_tv)|(?:musume|blake)_\d{2,3})\)',
    caseSensitive: false,
  );
  static final _cache = <String, ComposeRichTextDocument>{};
  static const maxLength = 65536;
  static const maxDepth = 16;
  static const maxNodes = 2048;

  static ComposeRichTextDocument parse(String source) {
    final hit = _cache[source];
    if (hit != null) return hit;
    final text =
        source.length > maxLength ? source.substring(0, maxLength) : source;
    final root = _Frame('', '');
    final stack = <_Frame>[root];
    var cursor = 0;
    var count = 0;
    var truncated = source.length > maxLength;
    var stopped = false;
    void appendText(String value) {
      if (value.isEmpty) return;
      stack.last.children.add(
        ComposeRichTextNode('text', decode(value), const []),
      );
    }

    for (final match in _tokens.allMatches(text)) {
      if (++count > maxNodes) {
        truncated = true;
        stopped = true;
        break;
      }
      appendText(text.substring(cursor, match.start));
      cursor = match.end;
      final token = match.group(0)!;
      if (token.startsWith('(')) {
        stack.last.children.add(ComposeRichTextNode('emoji', token, const []));
        continue;
      }
      final tag = match.group(2)!.toLowerCase();
      if (tag == 'br') {
        appendText('\n');
        continue;
      }
      if (match.group(1) == '/') {
        final index = stack.lastIndexWhere((frame) => frame.tag == tag);
        if (index > 0) {
          stack.removeRange(index, stack.length);
        } else {
          appendText(token);
        }
      } else {
        if (stack.length > maxDepth) {
          truncated = true;
          stopped = true;
          break;
        }
        final frame = _Frame(tag, decode(match.group(3) ?? ''));
        stack.last.children.add(frame);
        stack.add(frame);
      }
    }
    if (!stopped) {
      // 长度超限仍解析已接受部分；开放 mask 始终保持隐藏。
      appendText(text.substring(cursor));
    }
    final result = ComposeRichTextDocument(root.freeze().children, truncated);
    if (source.length <= 8192) {
      if (_cache.length >= 64) _cache.remove(_cache.keys.first);
      _cache[source] = result;
    }
    return result;
  }

  static String decode(String input) =>
      html
          .parseFragment(input.replaceAll('<', '&lt;').replaceAll('>', '&gt;'))
          .text ??
      input;

  static String plain(
    Iterable<ComposeRichTextNode> nodes, {
    bool revealMasks = false,
  }) =>
      nodes
          .map(
            (node) =>
                node.tag == 'mask' && !revealMasks
                    ? '•••'
                    : node.children.isEmpty
                    ? node.value
                    : plain(node.children, revealMasks: revealMasks),
          )
          .join();

  static Uri? safeUrl(String input) {
    var value = decode(
      input,
    ).trim().replaceAll(r'\_', '_').replaceAll(r'\/', '/');
    if (value.startsWith('//')) value = 'https:$value';
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.host == 'localhost' ||
        uri.host.endsWith('.local') ||
        uri.host.contains(':') ||
        RegExp(r'^[\d.]+$').hasMatch(uri.host)) {
      return null;
    }
    return uri;
  }
}
