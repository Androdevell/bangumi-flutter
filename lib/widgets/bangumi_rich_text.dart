import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/app_image_cache.dart';
import '../core/text/bbcode_document.dart';
import '../core/localization/app_localizations.dart';
import '../core/text/emoji_catalog.dart';
import 'rich_comment_image.dart';
import '../app/app_links.dart';

String? bangumiEmojiUrl(String smileId) {
  return EmojiCatalog.find(smileId)?.url;
}

String reactionImageUrl(String value) {
  const smileIds = <String, String>{
    '0': 'bgm67',
    '54': 'bgm38',
    '62': 'bgm46',
    '79': 'bgm63',
    '80': 'bgm64',
    '85': 'bgm69',
    '88': 'bgm72',
    '90': 'bgm74',
    '104': 'bgm88',
    '122': 'bgm106',
    '140': 'bgm124',
    '141': 'bgm125',
  };
  return bangumiEmojiUrl(smileIds[value] ?? 'bgm67')!;
}

class BangumiReactionImage extends StatelessWidget {
  const BangumiReactionImage({super.key, required this.value, this.size = 24});

  final String value;
  final double size;

  @override
  Widget build(BuildContext context) => CachedNetworkImage(
    imageUrl: reactionImageUrl(value),
    cacheManager: AppImageCache.manager,
    width: size,
    height: size,
    memCacheWidth: (size * 3).round(),
    fit: BoxFit.contain,
    placeholder: (_, __) => SizedBox(width: size, height: size),
    errorWidget: (_, __, ___) => Icon(Icons.add_reaction_outlined, size: size),
  );
}

class BangumiRichText extends StatelessWidget {
  const BangumiRichText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.selectable = true,
    this.originalColors = false,
    this.nodes,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final bool selectable;
  final bool originalColors;
  final List<ComposeRichTextNode>? nodes;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inlineWidth =
          constraints.hasBoundedWidth ? constraints.maxWidth : 320.0;
      final effectiveStyle = style ?? Theme.of(context).textTheme.bodyMedium;
      final document =
          nodes == null
              ? BangumiBbCode.parse(text)
              : ComposeRichTextDocument(nodes!, false);
      var images = 0;
      List<InlineSpan> render(
        List<ComposeRichTextNode> nodes,
        TextStyle inherited,
      ) =>
          nodes.map<InlineSpan>((node) {
            if (node.tag == 'text') {
              return TextSpan(text: node.value, style: inherited);
            }
            if (node.tag == 'mask') {
              return WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: inlineWidth),
                  child: _Spoiler(
                    key: ValueKey(node),
                    children: node.children,
                    style: inherited,
                    originalColors: originalColors,
                  ),
                ),
              );
            }
            if (node.tag == 'emoji') {
              final url = bangumiEmojiUrl(
                node.value.substring(1, node.value.length - 1),
              );
              if (url == null) return TextSpan(text: node.value);
              final size =
                  node.value.toLowerCase().startsWith('(bgm') ? 24.0 : 55.0;
              return WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: CachedNetworkImage(
                  imageUrl: url,
                  cacheManager: AppImageCache.manager,
                  width: size,
                  height: size,
                  memCacheWidth: (size * 3).round(),
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => Text(node.value),
                ),
              );
            }
            if (node.tag == 'img') {
              final uri = BangumiBbCode.safeUrl(
                BangumiBbCode.plain(node.children),
              );
              if (uri == null) return const TextSpan(text: '[img]');
              final deferred = ++images > 20;
              return WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: inlineWidth.clamp(0, 900).toDouble(),
                      maxHeight: 720,
                    ),
                    child: RichCommentImage(
                      key: ValueKey('$images:$uri'),
                      uri: uri,
                      deferred: deferred,
                    ),
                  ),
                ),
              );
            }
            if (node.tag == 'url') {
              final uri = BangumiBbCode.safeUrl(
                node.value.isEmpty
                    ? BangumiBbCode.plain(node.children)
                    : node.value,
              );
              if (uri != null) {
                return WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: inlineWidth),
                    child: TextButton(
                      onPressed: () => _openLink(context, uri),
                      child: Text(
                        BangumiBbCode.plain(node.children),
                        style: inherited.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                );
              }
            }
            var next = inherited;
            if (node.tag == 'b') {
              next = next.copyWith(fontWeight: FontWeight.bold);
            }
            if (node.tag == 'i') {
              next = next.copyWith(fontStyle: FontStyle.italic);
            }
            if (node.tag == 'u' || node.tag == 's') {
              next = next.copyWith(
                decoration: TextDecoration.combine([
                  if (next.decoration != null) next.decoration!,
                  node.tag == 'u'
                      ? TextDecoration.underline
                      : TextDecoration.lineThrough,
                ]),
              );
            }
            if (node.tag == 'size') {
              final size = double.tryParse(node.value);
              if (size != null && size.isFinite) {
                next = next.copyWith(fontSize: size.clamp(10, 28), height: 1.5);
              }
            }
            if (node.tag == 'color') {
              final color = _color(node.value);
              if (color != null) {
                final a = color.computeLuminance();
                final b =
                    Theme.of(context).colorScheme.surface.computeLuminance();
                final ratio =
                    (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
                if (originalColors || ratio >= 4.5) {
                  next = next.copyWith(color: color);
                }
              }
            }
            if (node.tag == 'quote') {
              return TextSpan(
                children: [
                  const TextSpan(text: '\n❝ '),
                  ...render(
                    node.children,
                    next.copyWith(fontStyle: FontStyle.italic),
                  ),
                  const TextSpan(text: '\n'),
                ],
              );
            }
            return TextSpan(children: render(node.children, next));
          }).toList();
      final richText = Text.rich(
        TextSpan(
          style: effectiveStyle,
          children: [
            ...render(document.nodes, effectiveStyle ?? const TextStyle()),
            if (document.truncated)
              TextSpan(text: '\n${_label(context, 'richTextLimited')}'),
          ],
        ),
        maxLines: maxLines,
        overflow: overflow,
      );
      return selectable ? SelectionArea(child: richText) : richText;
    },
  );
}

String _label(BuildContext context, String key) =>
    AppLocalizations.of(context).t(key);

Color? _color(String value) {
  const named = {
    'red': Colors.red,
    'green': Colors.green,
    'blue': Colors.blue,
    'orange': Colors.orange,
    'purple': Colors.purple,
    'pink': Colors.pink,
    'yellow': Colors.yellow,
    'cyan': Colors.cyan,
    'violet': Color(0xffee82ee),
    'khaki': Color(0xfff0e68c),
    'black': Colors.black,
    'white': Colors.white,
  };
  final name = value.trim().toLowerCase();
  if (named.containsKey(name)) return named[name];
  if (!RegExp(r'^#[0-9a-f]{6}$').hasMatch(name)) return null;
  return Color(0xff000000 | int.parse(name.substring(1), radix: 16));
}

Future<void> _openLink(BuildContext context, Uri uri) async {
  if (await AppLinkDispatcher.open(context, uri)) return;
  if (!context.mounted) return;
  final allowed = await showDialog<bool>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: Text(_label(context, 'openExternalLink')),
          content: SelectableText(uri.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_label(context, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_label(context, 'open')),
            ),
          ],
        ),
  );
  if (allowed == true) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _Spoiler extends StatefulWidget {
  const _Spoiler({
    super.key,
    required this.children,
    required this.style,
    required this.originalColors,
  });
  final List<ComposeRichTextNode> children;
  final TextStyle style;
  final bool originalColors;
  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _revealed = false;
  @override
  Widget build(BuildContext context) {
    if (_revealed) {
      return BangumiRichText(
        '',
        nodes: widget.children,
        style: widget.style,
        originalColors: widget.originalColors,
      );
    }
    return SelectionContainer.disabled(
      child: Semantics(
        button: true,
        label: _label(context, 'revealSpoiler'),
        child: TextButton(
          onPressed: () => setState(() => _revealed = true),
          style: TextButton.styleFrom(
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: const Text('•••'),
        ),
      ),
    );
  }
}
