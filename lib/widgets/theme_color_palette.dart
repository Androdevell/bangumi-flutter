import 'package:flutter/material.dart';
import '../core/localization/app_localizations.dart';

/// 调色盘仅更新页面草稿；保存由主题页面统一处理。
class ThemeColorPalette extends StatefulWidget {
  const ThemeColorPalette({
    super.key,
    required this.color,
    required this.onChanged,
  });
  final Color color;
  final ValueChanged<Color>? onChanged;

  @override
  State<ThemeColorPalette> createState() => _ThemeColorPaletteState();
}

class _ThemeColorPaletteState extends State<ThemeColorPalette> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color);

  @override
  void didUpdateWidget(ThemeColorPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.color != oldWidget.color && widget.color != _hsv.toColor()) {
      _hsv = HSVColor.fromColor(widget.color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final hsv = _hsv;
    final color = widget.color;
    final onChanged = widget.onChanged;
    void change(double hue, double saturation, double value) {
      final next = HSVColor.fromAHSV(
        1,
        hue.clamp(0, 360),
        saturation.clamp(0, 1),
        value.clamp(0, 1),
      );
      setState(() => _hsv = next);
      onChanged?.call(next.toColor());
    }

    return Column(
      children: [
        Semantics(
          label: s.t('themePalette'),
          child: LayoutBuilder(
            builder: (context, box) {
              void update(Offset point) =>
                  change(hsv.hue, point.dx / box.maxWidth, 1 - point.dy / 160);
              return GestureDetector(
                onPanDown:
                    onChanged == null ? null : (d) => update(d.localPosition),
                onPanUpdate:
                    onChanged == null ? null : (d) => update(d.localPosition),
                child: SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white,
                                HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (box.maxWidth * hsv.saturation - 8).clamp(
                          0,
                          box.maxWidth - 16,
                        ),
                        top: (160 * (1 - hsv.value) - 8).clamp(0, 144),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        for (final component in [
          (
            s.t('themeHue'),
            hsv.hue,
            360.0,
            (double v) => change(v, hsv.saturation, hsv.value),
          ),
          (
            s.t('themeSaturation'),
            hsv.saturation * 100,
            100.0,
            (double v) => change(hsv.hue, v / 100, hsv.value),
          ),
          (
            s.t('themeValue'),
            hsv.value * 100,
            100.0,
            (double v) => change(hsv.hue, hsv.saturation, v / 100),
          ),
        ])
          Row(
            children: [
              SizedBox(width: 82, child: Text(component.$1)),
              Expanded(
                child: Slider(
                  label: '${component.$1}: ${component.$2.round()}',
                  value: component.$2,
                  min: 0,
                  max: component.$3,
                  divisions: component.$3.toInt(),
                  onChanged: onChanged == null ? null : component.$4,
                ),
              ),
              SizedBox(
                width: 65,
                child: Semantics(
                  label: component.$1,
                  child: TextFormField(
                    key: ValueKey('${component.$1}:${component.$2.round()}'),
                    initialValue: '${component.$2.round()}',
                    enabled: onChanged != null,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      semanticCounterText: component.$1,
                    ),
                    onFieldSubmitted: (text) {
                      final value = double.tryParse(text);
                      if (value != null && value.isFinite) {
                        component.$4(value.clamp(0, component.$3));
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
