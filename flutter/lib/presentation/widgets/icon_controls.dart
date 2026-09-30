import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

/// An icon from assets/icons, tinted to the text colour.
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {super.key, this.size = 20, this.color});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/$name',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color ?? Palette.ink, BlendMode.srcIn),
  );
}

/// A small square icon button with a tooltip.
///
/// Shows either an SVG from assets/icons ([icon]) or a Material icon
/// ([iconData]). [selected] gives it the accent wash, for toggles.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    this.icon,
    this.iconData,
    required this.label,
    required this.onPressed,
    this.size = 28,
    this.tooltip,
    this.selected = false,
  }) : assert(icon != null || iconData != null);

  final String? icon;
  final IconData? iconData;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colour = onPressed == null
        ? Palette.faint
        : (selected ? Palette.accent : Palette.ink);
    return Tooltip(
      message: tooltip ?? label,
      child: Semantics(
        label: label,
        button: true,
        selected: selected,
        child: Material(
          color: selected ? Palette.wash : Colors.transparent,
          borderRadius: BorderRadius.circular(Metrics.radius),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(Metrics.radius),
            hoverColor: Palette.hover,
            child: SizedBox.square(
              dimension: size,
              child: Center(
                child: icon != null
                    ? AppIcon(icon!, size: 16, color: colour)
                    : Icon(iconData, size: 17, color: colour),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
