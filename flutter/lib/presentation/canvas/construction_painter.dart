part of 'scene_painter.dart';

/// Extra feedback for construction tools, separate from ordinary land paint.
extension _ConstructionPainter on ScenePainter {
  void _paintArcFeedback(Canvas canvas, ArcPreview preview) {
    final color = preview.valid ? Palette.valid : Palette.invalid;
    final curve = preview.curve;
    if (curve != null) {
      dashedPath(
        canvas,
        curvePath(curve, _camera),
        color,
        width: scene.appearance.lineWidth,
        dash: 7,
        gap: 5,
      );
    } else {
      // Two clicks cannot yet define a circle. This is a construction guide,
      // never an approximation of the eventual arc by its chord.
      _dashedLine(
        canvas,
        _camera.toScreen(preview.start),
        _camera.toScreen(preview.through),
        color,
        width: 1,
        dash: 2,
        gap: 4,
      );
      if (preview.end case final end?) {
        _dashedLine(
          canvas,
          _camera.toScreen(preview.through),
          _camera.toScreen(end),
          color,
          width: 1,
          dash: 2,
          gap: 4,
        );
      }
    }
    for (final point in [
      preview.start,
      preview.through,
      if (preview.end != null) preview.end!,
    ]) {
      canvas.drawCircle(_camera.toScreen(point), 3, Paint()..color = color);
    }
    if (preview.joinTarget != null && preview.end != null) {
      _joinRing(canvas, _camera.toScreen(preview.end!), preview.valid);
    }
  }

  /// The would-be polygon as a dashed outline, with a marker on the first
  /// click and each corner.
  void _paintPolygonFeedback(Canvas canvas, PolygonPreview preview) {
    final color = preview.valid ? Palette.accent : Palette.invalid;
    final corners = [for (final c in preview.corners) _camera.toScreen(c)];
    for (var i = 0; i < corners.length; i++) {
      _dashedLine(
        canvas,
        corners[i],
        corners[(i + 1) % corners.length],
        color,
        width: scene.appearance.lineWidth,
        dash: 7,
        gap: 5,
      );
    }
    for (final marker in [_camera.toScreen(preview.start), ...corners]) {
      canvas.drawCircle(marker, 3, Paint()..color = color);
    }
  }

  void _paintBooleanFeedback(Canvas canvas, BooleanPreview preview) {
    final document = preview.document ?? scene.document;
    final geometry = document.geometryOf(preview.layerId);
    final ids = preview.document == null
        ? [preview.operandId]
        : preview.resultIds;
    if (ids.isEmpty) return;
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final id in ids) {
      path.addPath(_regionPath(geometry, id: id), Offset.zero);
    }
    final color = preview.valid ? Palette.valid : Palette.invalid;
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.14));
    dashedPath(
      canvas,
      path,
      color,
      width: scene.appearance.lineWidth + 1,
      dash: 7,
      gap: 4,
    );
  }
}
