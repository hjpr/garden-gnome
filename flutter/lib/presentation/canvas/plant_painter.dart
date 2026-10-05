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
  ///
  /// All shadows go in one atlas draw and all pictures in another: one
  /// draw call per plant cost about 40 ms a frame zoomed out on a laptop.
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
    final half = image.width / 2;
    final pictureScale = side / image.width;
    // Shadows are lost under a few pixels' worth of leaves.
    final shadows = canopy >= _minShadowPixels;
    final disc = shadows ? _shadowDisc() : null;
    final discScale = canopy / _ShadowDisc.canopy;
    // The leaves reach about half the canopy from the centre, so the
    // shadow must be nearly as wide and pushed out to show past them.
    final drop = Offset(canopy * 0.11, canopy * 0.14);
    final visible = (Offset.zero & size).inflate(side);

    final at = <Offset>[];
    final turns = <double>[];
    final grows = <double>[];
    for (final p in layout.positions) {
      final screen = _camera.toScreen(p);
      if (!visible.contains(screen)) continue;
      at.add(screen);
      turns.add(_hashAt(p) * 2 * math.pi);
      // Each plant a little bigger or smaller (±8%), so a bed of one
      // picture does not look stamped. Display only.
      grows.add(0.92 + 0.16 * _hashAt(p + const Vec(7.1, 3.3)));
    }
    if (at.isEmpty) return true;

    if (disc != null) {
      const c = _ShadowDisc.side / 2;
      final transforms = Float32List(at.length * 4);
      final rects = Float32List(at.length * 4);
      for (var i = 0; i < at.length; i++) {
        final scale = discScale * grows[i];
        final centre = at[i] + drop * grows[i];
        transforms
          ..[i * 4] = scale
          ..[i * 4 + 1] = 0
          ..[i * 4 + 2] = centre.dx - scale * c
          ..[i * 4 + 3] = centre.dy - scale * c;
        rects
          ..[i * 4 + 2] = _ShadowDisc.side
          ..[i * 4 + 3] = _ShadowDisc.side;
      }
      canvas.drawRawAtlas(
        disc,
        transforms,
        rects,
        null,
        null,
        null,
        Paint()..filterQuality = FilterQuality.low,
      );
    }

    final transforms = Float32List(at.length * 4);
    final rects = Float32List(at.length * 4);
    for (var i = 0; i < at.length; i++) {
      final scale = pictureScale * grows[i];
      final cos = scale * math.cos(turns[i]), sin = scale * math.sin(turns[i]);
      transforms
        ..[i * 4] = cos
        ..[i * 4 + 1] = sin
        ..[i * 4 + 2] = at[i].dx - cos * half + sin * half
        ..[i * 4 + 3] = at[i].dy - sin * half - cos * half;
      rects
        ..[i * 4 + 2] = image.width.toDouble()
        ..[i * 4 + 3] = image.height.toDouble();
    }
    canvas.drawRawAtlas(
      image,
      transforms,
      rects,
      null,
      null,
      null,
      Paint()..filterQuality = FilterQuality.medium,
    );
    return true;
  }

  /// Plants narrower than this many pixels are drawn without a shadow.
  static const _minShadowPixels = 10.0;

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

/// One soft plant shadow, blurred once and stamped under every plant
/// instead of blurring a circle per plant each frame.
abstract final class _ShadowDisc {
  /// The canopy width, in pixels, the disc is drawn for.
  static const double canopy = 96;

  /// Room for the circle (0.47 canopy) and its blur (3 × 0.07 canopy).
  static const double side = 136;
}

ui.Image? _shadowDiscImage;

ui.Image _shadowDisc() => _shadowDiscImage ??= () {
  final recorder = ui.PictureRecorder();
  const c = _ShadowDisc.side / 2;
  Canvas(recorder).drawCircle(
    const Offset(c, c),
    _ShadowDisc.canopy * 0.47,
    Paint()
      ..color = _PlantColours.shadow
      ..maskFilter = const MaskFilter.blur(
        BlurStyle.normal,
        _ShadowDisc.canopy * 0.07,
      ),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(
    _ShadowDisc.side.toInt(),
    _ShadowDisc.side.toInt(),
  );
  picture.dispose();
  return image;
}();

abstract final class _PlantColours {
  static const leaf = Color(0xFF4F9A3A);
  static const wireLeaf = Color(0xFF3F8A4F);
  static const rim = Color(0xFF24541E);
  static const growOutline = Color(0xFF2F6B3F);
  static const shadow = Color(0x801E140A);
}
