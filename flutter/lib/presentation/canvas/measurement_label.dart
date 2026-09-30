import 'package:flutter/painting.dart';

import '../theme.dart';

void paintMeasurementLabel(
  Canvas canvas, {
  required String text,
  required Offset anchor,
  required Color color,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
    ),
    textDirection: TextDirection.ltr,
  );
  try {
    painter.layout();
    final at = anchor + const Offset(8, 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (at - const Offset(4, 2)) & Size(painter.width + 8, painter.height + 4),
        const Radius.circular(4),
      ),
      Paint()..color = Palette.paper.withValues(alpha: 0.9),
    );
    painter.paint(canvas, at);
  } finally {
    painter.dispose();
  }
}
