part of 'scene_painter.dart';

/// Wireframe colours per feature kind.
Color _featureColour(FeatureKind kind) => switch (kind) {
  FeatureKind.raisedBed => const Color(0xFF9A6A3A),
  FeatureKind.greenhouse => const Color(0xFF3F8C88),
  FeatureKind.highTunnel => const Color(0xFF6F7C8C),
};

/// Draws raised beds, greenhouses and high tunnels over all land: their
/// illustrations in the Render view, outlined footprints in Wireframe,
/// with the selected or hovered one ringed.
extension _FeaturePainter on ScenePainter {
  void _paintFeatures(Canvas canvas) {
    final preview = scene.preview;
    final moving = preview is FeatureMovePreview && !preview.placing
        ? preview.feature
        : null;
    final hovered = preview is FeatureHoverPreview ? preview.featureId : null;
    for (final saved in scene.document.features) {
      final feature = moving?.id == saved.id ? moving! : saved;
      _paintFeature(canvas, feature, ghost: false);
      final selected = feature.id == scene.selectedFeatureId;
      if (selected || feature.id == hovered || identical(feature, moving)) {
        _ringFeature(canvas, feature, selected: selected);
      }
    }
    if (preview is FeatureMovePreview && preview.placing) {
      _paintFeature(canvas, preview.feature, ghost: true);
    }
  }

  void _paintFeature(Canvas canvas, Feature feature, {required bool ghost}) {
    final ppm = _camera.pixelsPerMetreNow;
    final centre = _camera.toScreen(feature.centre);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: feature.length * ppm,
      height: feature.width * ppm,
    );
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(feature.rotation * math.pi / 180);
    final assets = scene.renderAssets;
    final picture = assets?.feature(feature.kind);
    final tunnel =
        feature.kind == FeatureKind.highTunnel &&
        (assets?.tunnelReady ?? false);
    if (scene.viewMode == ViewMode.render && (picture != null || tunnel)) {
      final alpha = ghost ? 0.55 : 1.0;
      // A tunnel is drawn at its length rounded to whole 5 ft sections.
      final drawn = tunnel
          ? Rect.fromCenter(
              center: Offset.zero,
              width: tunnelSections(feature.length) * tunnelSectionLength * ppm,
              height: rect.height,
            )
          : rect;
      // A soft shadow to the lower right lifts it off the ground.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          drawn.shift(
            Offset(drawn.shortestSide * 0.06, drawn.shortestSide * 0.1),
          ),
          Radius.circular(drawn.shortestSide * 0.08),
        ),
        Paint()
          ..color = Color.fromRGBO(30, 40, 20, 0.28 * alpha)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            math.max(1, drawn.shortestSide * 0.05),
          ),
      );
      final paint = Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, alpha);
      if (tunnel) {
        _paintTunnelSections(
          canvas,
          assets!,
          drawn,
          tunnelSections(feature.length),
          paint,
        );
      } else {
        _drawWhole(canvas, picture!, drawn, paint);
      }
    } else {
      final colour = _featureColour(feature.kind);
      canvas.drawRect(
        rect,
        Paint()..color = colour.withValues(alpha: ghost ? 0.08 : 0.16),
      );
      final outline = Paint()
        ..color = colour.withValues(alpha: ghost ? 0.6 : 1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = scene.appearance.lineWidth;
      canvas.drawRect(rect, outline);
      // A line along the length shows which way it runs.
      canvas.drawLine(
        rect.centerLeft,
        rect.centerRight,
        Paint()
          ..color = colour.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }
    canvas.restore();
  }

  void _drawWhole(Canvas canvas, ui.Image picture, Rect to, Paint paint) {
    canvas.drawImageRect(
      picture,
      Rect.fromLTWH(0, 0, picture.width.toDouble(), picture.height.toDouble()),
      to,
      paint,
    );
  }

  /// A high tunnel laid out end to end: the left end, the middle
  /// sections, then the right end, [count] sections in all. Each piece
  /// keeps its own proportions (an end holds more picture than a middle
  /// bay), and the row of pieces is scaled evenly to the drawn length, so
  /// nothing is stretched. Pieces overlap by a hair so no background line
  /// shows between them.
  void _paintTunnelSections(
    Canvas canvas,
    RenderAssets assets,
    Rect drawn,
    int count,
    Paint paint,
  ) {
    final pieces = [
      TunnelPiece.leftEnd,
      for (var i = 0; i < count - 2; i++) TunnelPiece.middle,
      TunnelPiece.rightEnd,
    ];
    final pixels = pieces.fold<double>(
      0,
      (sum, piece) => sum + assets.tunnel(piece)!.width,
    );
    final scale = drawn.width / pixels;
    var left = drawn.left;
    for (final (i, piece) in pieces.indexed) {
      final image = assets.tunnel(piece)!;
      final width = image.width * scale;
      final last = i == pieces.length - 1;
      _drawWhole(
        canvas,
        image,
        Rect.fromLTRB(
          left,
          drawn.top,
          last ? drawn.right : left + width + 0.5,
          drawn.bottom,
        ),
        paint,
      );
      left += width;
    }
  }

  /// The accent ring around a selected (solid) or hovered (light) feature.
  void _ringFeature(Canvas canvas, Feature feature, {required bool selected}) {
    final corners = [for (final c in feature.corners) _camera.toScreen(c)];
    final outline = Path()..addPolygon(corners, true);
    canvas.drawPath(
      outline,
      Paint()
        ..color = Palette.accent.withValues(alpha: selected ? 0.9 : 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.5 : 2,
    );
  }
}
