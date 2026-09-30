import 'package:flutter/material.dart';

/// A small rounded label, e.g. a timing or a stage.
class StatusChip extends StatelessWidget {
  const StatusChip(
    this.text, {
    super.key,
    required this.color,
    this.solid = false,
  });

  final String text;
  final Color color;
  final bool solid;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: solid ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: solid ? Colors.white : color,
      ),
    ),
  );
}
