import 'package:flutter/material.dart';
import '../app/app_theme.dart';
import '../core/localization/app_localizations.dart';
import '../core/settings/theme_preferences.dart';
import 'liquid_glass.dart';

class InterfaceStylePicker extends StatelessWidget {
  const InterfaceStylePicker({
    super.key,
    required this.value,
    required this.seed,
    this.onChanged,
  });
  final InterfaceStyle value;
  final Color seed;
  final ValueChanged<InterfaceStyle>? onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final s = AppLocalizations.of(context);
      final narrow = constraints.maxWidth < 420;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final style in InterfaceStyle.values)
            SizedBox(
              width:
                  narrow
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 12) / 2,
              child: Semantics(
                selected: value == style,
                child: Material(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: .86),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: BorderSide(
                      color:
                          value == style
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).dividerColor,
                      width: value == style ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('theme-style-${style.name}'),
                    onTap: onChanged == null ? null : () => onChanged!(style),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ExcludeSemantics(
                            child: SizedBox(
                              height: 112,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Theme(
                                  data:
                                      Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? AppTheme.dark(
                                            seed: seed,
                                            style: style,
                                          )
                                          : AppTheme.light(
                                            seed: seed,
                                            style: style,
                                          ),
                                  child: const _StylePreview(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s.t(
                                    style == InterfaceStyle.material
                                        ? 'styleMaterial'
                                        : 'styleLiquidGlass',
                                  ),
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                value == style
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked,
                                size: 22,
                                color:
                                    value == style
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.outline,
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            s.t(
                              style == InterfaceStyle.material
                                  ? 'styleMaterialHint'
                                  : 'styleLiquidGlassHint',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _StylePreview extends StatelessWidget {
  const _StylePreview();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppGlassBackground(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: scheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: .3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 28),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AdaptiveCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.play_circle_outline_rounded,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 6,
                              width: 80,
                              color: scheme.onSurface.withValues(alpha: .25),
                            ),
                            const SizedBox(height: 7),
                            Container(
                              height: 4,
                              width: 44,
                              color: scheme.primary.withValues(alpha: .3),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.favorite_outline_rounded,
                        size: 18,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
