import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Keeps the canonical gap fixed when text grows; native .icon factories
/// otherwise reduce their internal spacing at larger text scales.
class DeckButtonLabel extends StatelessWidget {
  const DeckButtonLabel({super.key, required this.icon, required this.label});
  final String icon, label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 7,
    children: [
      DeckButtonIcon(icon),
      Flexible(child: Text(label)),
    ],
  );
}

/// Canonical .button icons have their own device size, independent of text.
class DeckButtonIcon extends StatelessWidget {
  const DeckButtonIcon(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) =>
      DeckIcon(name, size: MediaQuery.sizeOf(context).width <= 520 ? 18 : 16);
}

/// The atlas' original 24-unit paths, including its stroke and clipping.
class DeckIcon extends StatelessWidget {
  const DeckIcon(
    this.name, {
    super.key,
    this.size = 20,
    this.color,
    this.label,
  });
  final String name;
  final double size;
  final Color? color;
  final String? label;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/brand/icons/$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(
      color ??
          IconTheme.of(context).color ??
          Theme.of(context).colorScheme.onSurface,
      BlendMode.srcIn,
    ),
    semanticsLabel: label,
    excludeFromSemantics: label == null,
  );
}
