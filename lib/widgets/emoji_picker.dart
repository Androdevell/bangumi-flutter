import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/text/emoji_catalog.dart';
import '../core/media/rich_image_policy.dart';
import '../core/network/app_image_cache.dart';
import '../core/localization/app_localizations.dart';

Future<String?> showEmojiPicker(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _EmojiPicker(),
    );

class _EmojiPicker extends StatefulWidget {
  const _EmojiPicker();
  @override
  State<_EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<_EmojiPicker> {
  String _family = 'tv';
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final recent = RichImagePolicy.instance.recentEmojis;
    final entries =
        _family == 'recent'
            ? recent
                .map(EmojiCatalog.find)
                .whereType<ComposeEmojiAsset>()
                .toList()
            : EmojiCatalog.entries.where((e) => e.family == _family).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .55,
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final family in ['recent', ...EmojiCatalog.families])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          strings.t(
                            family == 'recent'
                                ? 'recentEmojis'
                                : 'emoji_$family',
                          ),
                        ),
                        selected: _family == family,
                        onSelected: (_) => setState(() => _family = family),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                key: ValueKey(_family),
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 72,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final asset = entries[index];
                  return Tooltip(
                    message: '(${asset.code})',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        RichImagePolicy.instance.rememberEmoji(asset.code);
                        Navigator.pop(context, '(${asset.code})');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: CachedNetworkImage(
                          imageUrl: asset.url,
                          cacheManager: AppImageCache.manager,
                          memCacheWidth: 144,
                          fit: BoxFit.contain,
                          errorWidget:
                              (_, __, ___) => Text(
                                asset.code,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
