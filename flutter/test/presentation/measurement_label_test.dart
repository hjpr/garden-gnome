import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/presentation/canvas/measurement_label.dart';
import 'package:garden_gnome/presentation/theme.dart';

Future<Uint8List> _raster(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(240, 100);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return Uint8List.fromList(data!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

// The pre-extraction label recipe, kept independent of the shared renderer.
void _originalLabel(Canvas canvas, String label, Offset at, Color color) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  try {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'shared measurement labels preserve diameter and reference pixels',
    () async {
      for (final (label, color) in [
        ('⌀ 6.5 ft', Palette.accent),
        ('12 ft (not set)', const Color(0xFF376B95)),
      ]) {
        final expected = await _raster(
          (canvas) =>
              _originalLabel(canvas, label, const Offset(48, 36), color),
        );
        final actual = await _raster(
          (canvas) => paintMeasurementLabel(
            canvas,
            text: label,
            anchor: const Offset(40, 30),
            color: color,
          ),
        );
        expect(actual, orderedEquals(expected), reason: label);
      }
    },
  );
}
