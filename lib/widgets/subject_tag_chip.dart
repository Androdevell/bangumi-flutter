import 'package:flutter/material.dart';

class SubjectTagChip extends StatelessWidget {
  const SubjectTagChip({
    super.key,
    required this.name,
    required this.count,
    required this.onTap,
  });
  final String name;
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ActionChip(
    onPressed: onTap,
    label: Text.rich(
      TextSpan(
        children: [
          TextSpan(text: name, style: Theme.of(context).textTheme.labelLarge),
          TextSpan(
            text: '  $count',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );
}
