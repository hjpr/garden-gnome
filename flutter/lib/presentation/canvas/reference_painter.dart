part of 'scene_painter.dart';

/// Blue used for the reference image's outline, handles and line, so they
/// read as guides rather than land.
const _referenceBlue = Color(0xFF376B95);

/// Draws the reference picture under all land, with its outline, corner
/// handles when selected, and its reference line.
extension _ReferencePainter on ScenePainter {
  void _paintReference(Canvas canvas) {
    final preview = scene.preview;
    final moving = preview is ReferencePreview ? preview.image : null;
    // Bottom image first, so later images lie on top.
    for (final saved in scene.document.references) {
      final image = moving != null && moving.id == saved.id ? moving : saved;
      _paintReferenceImage(canvas, image, moving: identical(image, moving));
    }
  }

  void _paintReferenceImage(
    Canvas canvas,
    ReferenceImage image, {
    required bool moving,
  }) {
    final rect = Rect.fromPoints(
      _camera.toScreen(image.topLeft),
      _camera.toScreen(image.bottomRight),
    );
    final picture = scene.referencePictures[image.bytes];
    final opacity = scene.referenceOpacity?.call(image) ?? image.opacity;
    if (picture != null) {
      canvas.drawImageRect(
        picture,
        Rect.fromLTWH(
          0,
          0,
          picture.width.toDouble(),
          picture.height.toDouble(),
        ),
        rect,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, opacity)
          ..filterQuality = FilterQuality.medium,
      );
    } else {
      // Still decoding, or unreadable: keep its place visible.
      canvas.drawRect(
        rect,
        Paint()..color = Palette.hatch.withValues(alpha: 0.2),
      );
    }

    final selected = scene.selectedImageId == image.id || moving;
    canvas.drawRect(
      rect,
      Paint()
        ..color = _referenceBlue.withValues(alpha: selected ? 0.9 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 1.5 : 1,
    );
    if (selected && !image.locked) {
      for (final corner in [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ]) {
        final handle = Rect.fromCenter(center: corner, width: 9, height: 9);
        canvas.drawRect(handle, Paint()..color = Palette.paper);
        canvas.drawRect(
          handle,
          Paint()
            ..color = _referenceBlue
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    if (image.hasLine) {
      _paintReferenceLine(
        canvas,
        image.toWorld(image.lineStart!),
        image.toWorld(image.lineEnd!),
        _referenceBlue,
        label: image.isCalibrated
            ? scene.units.format(image.lineLength!)
            : '${scene.units.format(image.lineLength!)} (not set)',
      );
    }
    if (scene.referenceLineImageId == image.id) {
      if (scene.referenceLineStart case final start?) {
        _referenceMarker(
          canvas,
          _camera.toScreen(image.toWorld(start)),
          _referenceBlue,
        );
      }
    }
  }

  /// A reference line with end ticks and, when given, its length.
  void _paintReferenceLine(
    Canvas canvas,
    Vec from,
    Vec to,
    Color colour, {
    bool dashed = false,
    String? label,
  }) {
    final a = _camera.toScreen(from);
    final b = _camera.toScreen(to);
    if (dashed) {
      _dashedLine(canvas, a, b, colour, dash: 6, gap: 4, width: 2);
    } else {
      // A pale halo keeps the line readable on a busy photo.
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = Palette.paper.withValues(alpha: 0.8)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = colour
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
    _referenceMarker(canvas, a, colour);
    _referenceMarker(canvas, b, colour);
    if (label == null) return;
    paintMeasurementLabel(
      canvas,
      text: label,
      anchor: (a + b) / 2,
      color: colour,
    );
  }

  void _referenceMarker(Canvas canvas, Offset at, Color colour) {
    canvas.drawCircle(at, 5, Paint()..color = Palette.paper);
    canvas.drawCircle(
      at,
      5,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
