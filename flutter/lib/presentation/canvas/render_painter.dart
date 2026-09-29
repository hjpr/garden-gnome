part of 'scene_painter.dart';

/// Plain colours used before the textures load, and for edges.
abstract final class _RenderColours {
  static const wildGrass = Color(0xFF7FB255);
  static const lawn = Color(0xFF6DBE4A);
  static const lawnEdge = Color(0xFF3F8A30);
  static const dirt = Color(0xFFC99A64);
  static const dirtEdge = Color(0xFF8C6239);
  static const preppedSoil = Color(0xFFA0613D);
  static const loam = Color(0xFF432B1D);
  static const furrow = Color(0xFF9A6E48);
}

/// The Render view: the farm from above, painted with ground textures.
///
/// Open land is wild grass, a property is lawn, a zone is tidy dirt, flat
/// ground is prepared soil, and row ground is dirt with loamy rows laid
/// along its row settings. Textures are fixed to the ground, so they pan
/// and zoom with it.
extension _RenderPainter on ScenePainter {
  void _paintRenderGround(Canvas canvas, Size size, GardenDocument document) {
    _fillTextured(
      canvas,
      Offset.zero & size,
      RenderTexture.wildGrass,
      _RenderColours.wildGrass,
    );
    for (final layerId in document.drawingOrder) {
      final layer = document.layers[layerId]!;
      final region = document.geometryOf(layerId).region;
      if (region == null) continue;
      final path = regionPath(region, _camera);
      switch (layer.properties) {
        case PropertyProperties():
          if (!_fillBlended(canvas, size, path, RenderTexture.lawn)) {
            _fillTextured(
              canvas,
              path,
              RenderTexture.lawn,
              _RenderColours.lawn,
            );
            if (!_edgeDeferred) {
              _softEdge(canvas, path, _RenderColours.lawnEdge, 3);
            }
          }
        case ZoneProperties(:final ground, :final rows):
          _paintZoneGround(canvas, size, document, layerId, path, ground, rows);
      }
    }
  }

  void _paintZoneGround(
    Canvas canvas,
    Size size,
    GardenDocument document,
    String layerId,
    Path path,
    GroundType? ground,
    RowSpec rows,
  ) {
    final (texture, fallback) = ground == GroundType.flat
        ? (RenderTexture.preppedSoil, _RenderColours.preppedSoil)
        : (RenderTexture.dirt, _RenderColours.dirt);
    final blended = _fillBlended(canvas, size, path, texture);
    if (!blended) _fillTextured(canvas, path, texture, fallback);
    if (ground == GroundType.row) {
      canvas.save();
      canvas.clipPath(path);
      _paintRows(canvas, rowLayoutOf(document, layerId), rows);
      canvas.restore();
    }
    if (!blended && !_edgeDeferred) {
      _softEdge(canvas, path, _RenderColours.dirtEdge, 2.5);
    }
  }

  /// Whether blended edges are only waiting for the view to stop moving.
  /// Meanwhile patches get a plain clean cut, not the dark rim, so the
  /// look changes as little as possible when the blend comes back.
  bool get _edgeDeferred =>
      scene.viewMoving &&
      scene.renderAssets?.edgeShader(RenderTexture.lawn) != null;

  /// Fills [path] with [texture] whose edge blends into the ground below
  /// like game terrain: the edge wanders across a band [RenderTexture.edge]
  /// wide, pushed out where the texture is bright (blades, clods) and by
  /// slow noise, instead of following the drawn outline exactly.
  ///
  /// How: in a layer, the texture is painted past the outline, then cut by
  /// a mask. The mask is a blurred copy of the outline (1 deep inside,
  /// fading to 0 outside) plus the shader's "reach" for each spot,
  /// thresholded by a colour filter into a ragged, anti-aliased edge.
  ///
  /// Returns false (drawing nothing) when the shader is not ready, the
  /// band is under a pixel wide, or the view is moving (the two layers
  /// per patch halve the frame rate), so the caller draws a plain fill.
  bool _fillBlended(
    Canvas canvas,
    Size size,
    Path path,
    RenderTexture texture,
  ) {
    final assets = scene.renderAssets;
    final edgeShader = assets?.edgeShader(texture);
    final ground = assets?.groundShader(texture);
    if (edgeShader == null ||
        ground == null ||
        texture.edge <= 0 ||
        scene.viewMoving) {
      return false;
    }
    final band = texture.edge * _camera.pixelsPerMetreNow;
    if (band < 1.5) return false;
    // Coverage runs through 0.2..0.8 over about 1.7 sigma of blur.
    final sigma = band / 1.7;
    final bounds = path
        .getBounds()
        .inflate(sigma * 3)
        .intersect((Offset.zero & size).inflate(sigma * 3));
    if (bounds.isEmpty) return true;

    // The edge can only land where the blurred outline is partly covered:
    // a band about 2.5 sigma either side of it. Shader work is kept to the
    // patch plus that band, and the reach pass to the band alone, so a
    // large patch costs little more than a plain fill.
    final edgeBand = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sigma * 5;
    final texturePaint = Paint()..shader = _groundShader(ground, texture);
    canvas.saveLayer(bounds, Paint());
    canvas.drawPath(path, texturePaint);
    canvas.drawPath(path, edgeBand..shader = texturePaint.shader);
    canvas.saveLayer(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..colorFilter = const ColorFilter.matrix(_edgeThreshold),
    );
    canvas.drawRect(bounds, Paint()..color = const Color(0xFF000000));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
    );
    canvas.drawPath(
      path,
      edgeBand
        ..blendMode = BlendMode.plus
        ..shader = _groundShader(edgeShader, texture, edge: true),
    );
    canvas.restore();
    canvas.restore();
    return true;
  }

  /// Each row as a mounded strip of loam: a soft furrow shadow on the
  /// lower-right side, the loam itself, then a lit ridge toward the
  /// upper-left, so rows read as raised above the dirt paths.
  void _paintRows(Canvas canvas, RowLayout? layout, RowSpec rows) {
    if (layout == null || layout.runs.isEmpty) return;
    final ppm = _camera.pixelsPerMetreNow;
    final width = rows.width * ppm;
    if (width < 0.6) return; // Rows thinner than a pixel read as noise.
    // Each run is pulled in by half a row width at both ends, so its
    // round cap ends at the zone edge like the rounded end of a mound.
    final strips = Path();
    for (final run in layout.runs) {
      final a = _camera.toScreen(run.start), b = _camera.toScreen(run.end);
      final length = (b - a).distance;
      if (length < 1) continue;
      final inset = (b - a) / length * math.min(width / 2, length / 2);
      strips
        ..moveTo(a.dx + inset.dx, a.dy + inset.dy)
        ..lineTo(b.dx - inset.dx, b.dy - inset.dy);
    }
    // Light comes from the upper left: shadow falls to the lower right,
    // across the row whichever way it runs.
    final (ax, ay) = rows.along;
    var across = Offset(-ay, ax);
    if (across.dx + across.dy < 0) across = -across;
    Paint band(double w, Color colour, {double blur = 0}) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = colour
      ..maskFilter = blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur) : null;

    canvas.drawPath(
      strips.shift(across * (width * 0.16)),
      band(
        width * 1.02,
        _RenderColours.furrow.withValues(alpha: 0.45),
        blur: math.max(0.6, width * 0.07),
      ),
    );
    final loam = band(width, _RenderColours.loam)
      ..colorFilter = const ColorFilter.matrix(_liftLoam);
    _applyTexture(loam, RenderTexture.loam);
    canvas.drawPath(strips, loam);
    if (width > 5) {
      // A darker lower flank and a lit crest give the mound its shape.
      canvas.drawPath(
        strips.shift(across * (width * 0.3)),
        band(width * 0.4, const Color(0x1F3A2210), blur: width * 0.08),
      );
      canvas.drawPath(
        strips.shift(across * (-width * 0.18)),
        band(width * 0.22, const Color(0x33FFE2B8), blur: width * 0.08),
      );
    }
  }

  /// Fills [area] (a path or a rectangle) with [texture] tiled across the
  /// ground, or with [fallback] while the picture loads.
  void _fillTextured(
    Canvas canvas,
    Object area,
    RenderTexture texture,
    Color fallback,
  ) {
    final paint = Paint()..color = fallback;
    _applyTexture(paint, texture);
    switch (area) {
      case Rect rect:
        canvas.drawRect(rect, paint);
      case Path path:
        canvas.drawPath(path, paint);
    }
  }

  /// Gives [paint] a repeating [texture] fixed to the world, one repeat
  /// per [RenderTexture.metres] of ground. Leaves the plain colour when
  /// the picture has not loaded.
  void _applyTexture(Paint paint, RenderTexture texture) {
    final assets = scene.renderAssets;
    final ground = assets?.groundShader(texture);
    if (ground != null) {
      paint.shader = _groundShader(ground, texture);
      return;
    }
    final image = assets?.texture(texture);
    if (image == null) return;
    final scale = texture.metres * _camera.pixelsPerMetreNow / image.width;
    final origin = _camera.toScreen(Vec.zero);
    paint
      ..filterQuality = FilterQuality.medium
      ..shader = ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        Float64List.fromList([
          scale, 0, 0, 0, //
          0, scale, 0, 0,
          0, 0, 1, 0,
          origin.dx, origin.dy, 0, 1,
        ]),
      );
  }

  /// Sets the non-repeating ground shader's uniforms for this frame (the
  /// order matches the uniforms in shaders/ground.frag).
  ui.FragmentShader _groundShader(
    ui.FragmentShader shader,
    RenderTexture texture, {
    bool edge = false,
  }) {
    final image = scene.renderAssets!.texture(texture)!;
    final origin = _camera.toScreen(Vec.zero);
    final tint = texture.tint;
    final values = [
      origin.dx, origin.dy, // uOrigin
      _camera.pixelsPerMetreNow, // uPxPerMetre
      texture.metres, // uMetres
      image.width.toDouble(), image.height.toDouble(), // uTexSize
      texture.seed, // uSeed
      texture == RenderTexture.loam ? 0.0 : 1.0, // uRotate
      texture.variation, // uVariation
      tint.r, tint.g, tint.b, tint.a, // uTint
      ...scene.renderAssets!.meanColour(texture), // uMean
      edge ? _edgeReach : 0.0, texture.edgeNoise, // uEdge
    ];
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    shader.setImageSampler(0, image);
    return shader;
  }

  /// Lifts the dark loam texture to just below the dirt paths' colour
  /// while keeping its grain: colour x 1.3 plus a warm offset, which moves
  /// the loam's average (67, 43, 29) to about (160, 115, 74), a little
  /// darker than the dirt's (189, 135, 87). Offsets are in 0..255 units.
  static const _liftLoam = <double>[
    1.3, 0, 0, 0, 73, //
    0, 1.3, 0, 0, 59,
    0, 0, 1.3, 0, 36,
    0, 0, 0, 1, 0,
  ];

  /// How far, in mask units, texture detail and noise can push an edge.
  static const _edgeReach = 0.6;

  /// Turns the edge mask (red = outline coverage + reach) into alpha:
  /// opaque above 0.8, clear below, over a short ramp so the ragged edge
  /// stays anti-aliased but crisp. Offsets are in 0..255 units.
  static const _edgeThreshold = <double>[
    0, 0, 0, 0, 255, //
    0, 0, 0, 0, 255,
    0, 0, 0, 0, 255,
    12, 0, 0, 0, -12 * 0.8 * 255,
  ];

  /// A soft darker rim just inside a patch's edge, like a trimmed border,
  /// and a thin crisp line on the edge itself.
  void _softEdge(Canvas canvas, Path path, Color colour, double width) {
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 3
        ..color = colour.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.9),
    );
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = colour.withValues(alpha: 0.7),
    );
  }

  /// Wireframe: a zone with row ground shows its rows as thin strips, so
  /// the layout can be checked while drawing.
  void _paintWireRows(Canvas canvas, GardenDocument document, String layerId) {
    final layout = rowLayoutOf(document, layerId);
    if (layout == null || layout.runs.isEmpty) return;
    final ppm = _camera.pixelsPerMetreNow;
    final width = layout.spec.width * ppm;
    if (width < 2) return;
    final layer = document.layers[layerId]!;
    final colour = layerColor(layer);
    final strips = Path();
    for (final run in layout.runs) {
      final a = _camera.toScreen(run.start), b = _camera.toScreen(run.end);
      strips
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    }
    final region = document.geometryOf(layerId).region!;
    canvas.save();
    canvas.clipPath(regionPath(region, _camera));
    canvas.drawPath(
      strips,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = colour.withValues(alpha: 0.16),
    );
    canvas.restore();
  }
}

/// A zone's rows for this document, worked out once per document and
/// zone; null for layers without row ground or without land.
RowLayout? rowLayoutOf(GardenDocument document, String layerId) {
  final cache = _rowLayouts[document] ??= {};
  if (cache.containsKey(layerId)) return cache[layerId];
  return cache[layerId] = document.rowLayoutOf(layerId);
}

final _rowLayouts = Expando<Map<String, RowLayout?>>('row layouts');
