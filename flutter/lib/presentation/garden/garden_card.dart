import 'package:flutter/material.dart';

import '../theme.dart';

/// A white rounded card with an optional small-caps title, the building
/// block of the growing tools' layouts.
class GardenCard extends StatelessWidget {
  const GardenCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(12),
    this.fill = true,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  /// Whether the body fills the card's height (the card must then have a
  /// bounded height), or the card shrinks to its body.
  final bool fill;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Palette.paper,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Palette.panelBorder),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            SizedBox(
              height: 38,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title!.toUpperCase(),
                        style: sectionTitleStyle.copyWith(color: Palette.ink),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            ),
          // The same line as the card's border, so the title reads as its
          // own section.
          if (title != null) const Divider(color: Palette.panelBorder),
          if (fill)
            Expanded(
              child: Padding(padding: padding, child: child),
            )
          else
            Padding(padding: padding, child: child),
        ],
      ),
    ),
  );
}
