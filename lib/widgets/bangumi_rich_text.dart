import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../core/network/app_image_cache.dart';

final _richTokenPattern = RegExp(
  r'(\(bgm(?:\d+|124_tv)\)|\[img\](https?://[^\[]+)\[/img\])',
  caseSensitive: false,
);

final _bbCodePattern = RegExp(
  r'\[/?(?:b|i|u|s|mask|size(?:=\d+)?|color(?:=[^\]]+)?|quote(?:=[^\]]+)?|url(?:=[^\]]+)?)\]',
  caseSensitive: false,
);

String? bangumiEmojiUrl(String smileId) {
  final normalized = smileId.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9_]'),
    '',
  );
  if (!normalized.startsWith('bgm')) return null;
  if (normalized == 'bgm124_tv') {
    return 'https://lain.bgm.tv/img/smiles/tv/101.gif';
  }
  final id = int.tryParse(normalized.substring(3));
  if (id == null) return null;
  if (id >= 1 && id <= 23) {
    final extension = id == 11 || id == 23 ? 'gif' : 'png';
    return 'https://lain.bgm.tv/img/smiles/bgm/${id.toString().padLeft(2, '0')}.$extension';
  }
  if (id >= 24 && id <= 123) {
    return 'https://lain.bgm.tv/img/smiles/tv/${(id - 23).toString().padLeft(2, '0')}.gif';
  }
  if (id == 124) return 'https://lain.bgm.tv/img/smiles/tv/101.png';
  if (id == 125) return 'https://lain.bgm.tv/img/smiles/tv/102.gif';
  if (id >= 200 && id <= 238) {
    return 'https://lain.bgm.tv/img/smiles/tv_vs/bgm_$id.png';
  }
  return null;
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
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? Theme.of(context).textTheme.bodyMedium;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _richTokenPattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(text: _plainText(text.substring(cursor, match.start))),
        );
      }
      final token = match.group(0)!;
      if (token.toLowerCase().startsWith('(bgm')) {
        final url = bangumiEmojiUrl(token.substring(1, token.length - 1));
        if (url == null) {
          spans.add(TextSpan(text: token));
        } else {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: CachedNetworkImage(
                  imageUrl: url,
                  cacheManager: AppImageCache.manager,
                  width: 24,
                  height: 24,
                  memCacheWidth: 72,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => Text(token),
                ),
              ),
            ),
          );
        }
      } else {
        final imageUrl = match.group(2)!;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 320,
                  maxHeight: 240,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    cacheManager: AppImageCache.manager,
                    fit: BoxFit.contain,
                    errorWidget:
                        (_, __, ___) => const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: _plainText(text.substring(cursor))));
    }

    final richText = Text.rich(
      TextSpan(style: effectiveStyle, children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
    return selectable ? SelectionArea(child: richText) : richText;
  }
}

String _plainText(String input) {
  final normalized = input
      .replaceAll(RegExp(r'\[br\s*/?\]', caseSensitive: false), '\n')
      .replaceAllMapped(
        RegExp(
          r'\[url(?:=[^\]]+)?\](.*?)\[/url\]',
          caseSensitive: false,
          dotAll: true,
        ),
        (match) => match.group(1) ?? '',
      )
      .replaceAll(_bbCodePattern, '')
      .replaceAll(RegExp(r'\[/url\]', caseSensitive: false), '');
  return html.parseFragment(normalized).text ?? '';
}
