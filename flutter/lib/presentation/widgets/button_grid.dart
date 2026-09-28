import 'package:flutter/material.dart';

import '../theme.dart';

/// Buttons in a light tray, [columns] to a row. Further buttons wrap onto
/// new rows; every button keeps the same width, so a short row lines up
/// with the rows above. Shared by Drawing tools and Operations so every
/// button in the left dock is the same size.
class ButtonGrid extends StatelessWidget {
  const ButtonGrid({super.key, required this.children});

  static const columns = 3;
  static const _gap = 3.0;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Palette.field,
      borderRadius: BorderRadius.circular(Metrics.radius + 2),
    ),
    child: Column(
      children: [
        for (var start = 0; start < children.length; start += columns) ...[
          if (start > 0) const SizedBox(height: _gap),
          Row(
            children: [
              for (var i = start; i < start + columns; i++) ...[
                if (i > start) const SizedBox(width: _gap),
                Expanded(
                  child: i < children.length ? children[i] : const SizedBox(),
                ),
              ],
            ],
          ),
        ],
      ],
    ),
  );
}
