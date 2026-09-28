part of 'scene_painter.dart';

/// Extra feedback for construction tools, separate from ordinary land paint.
extension _ConstructionPainter on ScenePainter {
  void _paintArcFeedback(Canvas canvas, ArcPreview preview) {
    final color = preview.valid ? Palette.valid : Palette.invalid;
    final curve = preview.curve;
    final points = [
      preview.start,
      ?preview.through,
      ?preview.end,
    ].map(_camera.toScreen).toList();
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
      for (var i = 1; i < points.length; i++) {
        _dashedLine(
          canvas,
          points[i - 1],
          points[i],
          color,
          width: 1,
          dash: 2,
          gap: 4,
        );
      }
    }
    for (final point in points) {
      canvas.drawCircle(point, 3, Paint()..color = color);
    }
    if (preview.joinTarget != null && preview.end != null) {
      _joinRing(canvas, _camera.toScreen(preview.end!), preview.valid);
    }
  }

  /// The next Curve piece as a dashed Bézier curve, with the handles being
  /// pulled out at the pointer end drawn as thin lines to dots.
  void _paintCurveFeedback(Canvas canvas, CurvePreview preview) {
    final color = preview.valid ? Palette.accent : Palette.invalid;
    final to = _camera.toScreen(preview.to);
    if (preview.from case final from?) {
      dashedPath(
        canvas,
        bezierPath(
          CubicBezier(from, preview.fromHandle!, preview.toHandle, preview.to),
          _camera,
        ),
        color,
        width: scene.appearance.lineWidth,
        dash: 7,
        gap: 5,
      );
    }
    if (preview.outHandle != preview.to) {
      _paintHandleLine(canvas, preview.to, preview.toHandle, color);
      _paintHandleLine(canvas, preview.to, preview.outHandle, color);
    }
    if (preview.joinTarget != null) {
      _joinRing(canvas, to, preview.valid);
    } else {
      canvas.drawCircle(to, 3, Paint()..color = color);
    }
  }

  /// A Bézier handle: a thin line from its point to a small hollow dot.
  void _paintHandleLine(Canvas canvas, Vec anchor, Vec tip, Color color) {
    final a = _camera.toScreen(anchor);
    final b = _camera.toScreen(tip);
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = 1,
    );
    canvas.drawCircle(b, HandleReach.dot, Paint()..color = Palette.paper);
    canvas.drawCircle(
      b,
      HandleReach.dot,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  /// The Bézier handles of the selected curves, so Select can drag them.
  void _paintCurveHandles(Canvas canvas, Geometry geometry) {
    for (final handle in curveHandlesFor(geometry, scene.selection)) {
      _paintHandleLine(canvas, handle.anchor, handle.tip, Palette.accent);
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
