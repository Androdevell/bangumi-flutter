import 'package:flutter/material.dart';

import '../../widgets/bangumi_rich_text.dart';

const bangumiReactions = <String, String>{
  '0': '👍',
  '54': '😊',
  '62': '😆',
  '79': '😮',
  '80': '😢',
  '85': '😠',
  '88': '🤔',
  '90': '🎉',
  '104': '👀',
  '122': '💖',
  '140': '🤝',
  '141': '🔥',
};

Future<String?> showReactionPicker(
  BuildContext context, {
  String? selectedValue,
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  builder:
      (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选择一个表情', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reaction in bangumiReactions.entries)
                    IconButton.filledTonal(
                      tooltip: reaction.key,
                      isSelected: reaction.key == selectedValue,
                      onPressed: () => Navigator.pop(context, reaction.key),
                      icon: BangumiReactionImage(value: reaction.key),
                    ),
                ],
              ),
              if (selectedValue != null) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => Navigator.pop(context, ''),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  label: const Text('取消当前表情'),
                ),
              ],
            ],
          ),
        ),
      ),
);

class ReactionSummary extends StatelessWidget {
  const ReactionSummary({super.key, required this.reactions});

  final Map<String, int> reactions;

  @override
  Widget build(BuildContext context) {
    final visible = reactions.entries.where((item) => item.value > 0).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children: [
        for (final item in visible)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BangumiReactionImage(value: item.key, size: 20),
                const SizedBox(width: 5),
                Text('${item.value}'),
              ],
            ),
          ),
      ],
    );
  }
}
