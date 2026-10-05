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
      _paintPlantLayout(canvas, size, layout, layerId);
    }
  }

  void _paintPlantLayout(
    Canvas canvas,
    Size size,
    PlantLayout layout,
    String layerId,
  ) {
    final ppm = _camera.pixelsPerMetreNow;
    final plantPixels = layout.seed.footprint * ppm;
    if (scene.viewMode == ViewMode.render &&
        _paintPlantPictures(canvas, size, layout, layerId)) {
      return;
    }
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
    // Neighbours along the closer spacing just touch.
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

  /// Draws each plant as its overhead picture, at its crop's mature
  /// canopy (PlantArt.canopyOf), each turned by its own fixed angle so a
  /// row does not look stamped, over a soft shadow toward the lower right.
  /// Returns false, drawing nothing, when the crop has no picture, it has
  /// not loaded yet, or plants are too small or too many to draw singly.
  bool _paintPlantPictures(
    Canvas canvas,
    Size size,
    PlantLayout layout,
    String layerId,
  ) {
    final cropId = scene.plantCropIds[layerId];
    final kind = PlantArt.kindOf(cropId);
    final spread = PlantArt.canopyOf(cropId);
    if (kind == null || spread == null) return false;
    if (layout.positions.length < layout.count) return false;
    final ppm = _camera.pixelsPerMetreNow;
    final canopy = spread * ppm;
    if (canopy < _minPlantPixels * 2) return false;
    final image = scene.renderAssets?.plant(kind);
    if (image == null) return false;

    // The square picture is a little larger than the canopy it holds.
    final side = canopy / (1 - 2 * PlantArt.spriteMargin);
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final target = Rect.fromCenter(
      center: Offset.zero,
      width: side,
      height: side,
    );
    final picture = Paint()..filterQuality = FilterQuality.medium;
    final shadow = Paint()
      ..color = _PlantColours.shadow
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, canopy * 0.07);
    // The leaves reach about half the canopy from the centre, so the
    // shadow must be nearly as wide and pushed out to show past them.
    final drop = Offset(canopy * 0.11, canopy * 0.14);
    final visible = (Offset.zero & size).inflate(side);
    for (final p in layout.positions) {
      final at = _camera.toScreen(p);
      if (!visible.contains(at)) continue;
      final turn = _hashAt(p);
      // Each plant a little bigger or smaller (±8%), so a bed of one
      // picture does not look stamped. Display only.
      final grow = 0.92 + 0.16 * _hashAt(p + const Vec(7.1, 3.3));
      canvas.drawCircle(at + drop * grow, canopy * 0.47 * grow, shadow);
      canvas
        ..save()
        ..translate(at.dx, at.dy)
        ..rotate(turn * 2 * math.pi)
        ..scale(grow);
      canvas.drawImageRect(image, source, target, picture);
      canvas.restore();
    }
    return true;
  }

  /// A fixed number in 0..1 for world position [p], so each plant keeps
  /// its turn and size as the view pans and zooms.
  static double _hashAt(Vec p) {
    final h = math.sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453;
    return h - h.floorToDouble();
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
  static const shadow = Color(0x801E140A);
}
