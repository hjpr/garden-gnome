part of 'scene_painter.dart';

/// Grow zones: a dashed outline so they read as a planting plan laid over
/// the soil, and the plants their seed puts there.
extension _PlantPainter on ScenePainter {
  /// Plants are drawn one by one once each is at least this many pixels
  /// across; zoomed further out, their lines are drawn instead.
  static const _minPlantPixels = 3.0;

  void _paintPlants(Canvas canvas, Size size, GardenDocument document) {
    for (final layerId in document.drawingOrder) {
      if (!scene.shows(layerId)) continue;
      final layout = document.plantLayoutOf(layerId);
      if (layout == null || layout.count == 0) continue;
      _paintPlantLayout(canvas, size, layout);
    }
  }

  void _paintPlantLayout(Canvas canvas, Size size, PlantLayout layout) {
    final ppm = _camera.pixelsPerMetreNow;
    final plantPixels = layout.seed.size * ppm;
    final colour = scene.viewMode == ViewMode.render
        ? _PlantColours.leaf
        : _PlantColours.wireLeaf;
    if (plantPixels < _minPlantPixels ||
        layout.positions.length < layout.count) {
      // Too small (or too many) to draw one at a time: a line per row.
      final lines = Path();
      for (final run in layout.lines) {
        final a = _camera.toScreen(run.start), b = _camera.toScreen(run.end);
        lines
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      }
      canvas.drawPath(
        lines,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.5, math.min(plantPixels, 6))
          ..color = colour.withValues(alpha: 0.75),
      );
      return;
    }
    // Size is the footprint diameter; the empty gap only moves centres.
    final radius = plantPixels / 2;
    final fill = Paint()..color = colour.withValues(alpha: 0.85);
    final rim = Paint()
      ..color = _PlantColours.rim
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius > 4 ? 1 : 0.5;
    final visible = Offset.zero & size;
    for (final p in layout.positions) {
      final at = _camera.toScreen(p);
      if (!visible.inflate(radius).contains(at)) continue;
      canvas.drawCircle(at, radius, fill);
      if (radius > 2) canvas.drawCircle(at, radius, rim);
    }
  }

  /// Grow zones get a dashed outline on top of everything else on the
  /// land, so they read as a plan laid over the soil.
  void _paintGrowOutlines(Canvas canvas, GardenDocument document) {
    for (final layerId in document.drawingOrder) {
      if (!scene.shows(layerId)) continue;
      final layer = document.layers[layerId]!;
      final properties = layer.properties;
      if (properties is! ZoneProperties || !properties.isGrow) continue;
      final region = document.geometryOf(layerId).region;
      if (region == null) continue;
      dashedPath(
        canvas,
        regionPath(region, _camera),
        _PlantColours.growOutline,
        width: 1.5,
        dash: 6,
        gap: 4,
      );
    }
  }
}

abstract final class _PlantColours {
  static const leaf = Color(0xFF4F9A3A);
  static const wireLeaf = Color(0xFF3F8A4F);
  static const rim = Color(0xFF24541E);
  static const growOutline = Color(0xFF2F6B3F);
}
