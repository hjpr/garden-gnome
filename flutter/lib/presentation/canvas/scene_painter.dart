import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../application/camera.dart';
import '../../application/hit_testing.dart';
import '../../application/previews.dart';
import '../../application/workspace_settings.dart';
import '../../domain/document.dart';
import '../../domain/fill_patterns.dart';
import '../../domain/geometry.dart';
import '../../domain/land_rules.dart';
import '../../domain/layer.dart';
import '../../domain/reference_image.dart';
import '../../domain/units.dart';
import '../../domain/vec.dart';
import '../theme.dart';
import 'curve_paths.dart';
import 'pattern_painter.dart';

part 'construction_painter.dart';
part 'reference_painter.dart';

/// Everything the painter needs, gathered so painting never reads the
/// controller or changes state.
class SceneState {
  const SceneState({
    required this.document,
    required this.camera,
    required this.appearance,
    required this.selectedLayerId,
    required this.selection,
    required this.preview,
    required this.lineAnchor,
    required this.joinStart,
    this.units = Units.feet,
    this.referencePictures = const {},
    this.referenceOpacity,
    this.selectedImageId,
    this.referenceLineImageId,
    this.referenceLineStart,
  });

  final GardenDocument document;
  final Camera camera;
  final Appearance appearance;
  final String? selectedLayerId;
  final Set<String> selection;
  final Preview? preview;
  final String? lineAnchor;
  final String? joinStart;

  /// How lengths such as a circle's diameter are labelled.
  final Units units;

  /// Decoded reference pictures by their bytes; null while loading.
  final Map<Uint8List, ui.Image?> referencePictures;

  /// Opacity to draw each reference image with (live while its slider
  /// moves), or null to use the saved values.
  final double Function(ReferenceImage image)? referenceOpacity;

  /// The reference image showing corner handles, if any.
  final String? selectedImageId;

  /// The image a reference line is being drawn on, and its first end in
  /// that image's pixels.
  final String? referenceLineImageId;
  final Vec? referenceLineStart;
}

/// Draws the grid, every layer, and the current tool feedback.
class ScenePainter extends CustomPainter {
  ScenePainter(this.scene);

  final SceneState scene;

  Camera get _camera => scene.camera;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawColor(Palette.canvas, BlendMode.src);
    _paintGrid(canvas, size);
    _paintReference(canvas);

    // While dragging, the drawing is shown as it would be if released now.
    final move = scene.preview is MovePreview
        ? scene.preview as MovePreview
        : null;
    final boolean = scene.preview is BooleanPreview
        ? scene.preview as BooleanPreview
        : null;
    final document = boolean?.document ?? move?.document ?? scene.document;
    for (final layerId in document.drawingOrder) {
      _paintLayer(canvas, document, layerId);
    }

    final selectedId = scene.selectedLayerId;
    if (selectedId != null && document.layers.containsKey(selectedId)) {
      _paintSelectedLayerDetail(canvas, document.geometryOf(selectedId), move);
    }
    if (move != null) _paintMovedLines(canvas, document, move);
    _paintPreview(canvas, size);
  }

  // -------------------------------------------------------------------- grid

  void _paintGrid(Canvas canvas, Size size) {
    final a = scene.appearance;
    final paint = Paint()
      ..color = Color(a.gridColor).withValues(alpha: a.gridOpacity)
      ..strokeWidth = a.gridThickness;
    final cell = _camera.gridCellMetres;
    final topLeft = _camera.toWorld(Offset.zero);
    final bottomRight = _camera.toWorld(Offset(size.width, size.height));
    final lines = LineBatch();
    for (
      var x = (topLeft.x / cell).floor() * cell;
      x <= bottomRight.x;
      x += cell
    ) {
      final sx = _camera.toScreen(Vec(x, 0)).dx;
      lines.add(Offset(sx, 0), Offset(sx, size.height));
    }
    for (
      var y = (topLeft.y / cell).floor() * cell;
      y <= bottomRight.y;
      y += cell
    ) {
      final sy = _camera.toScreen(Vec(0, y)).dy;
      lines.add(Offset(0, sy), Offset(size.width, sy));
    }
    lines.draw(canvas, paint);
  }

  // ------------------------------------------------------------------ layers

  /// Active land gets a light fill. Closed land that is not active is
  /// hatched. Invalid land is drawn in red with dashed lines, so it stands
  /// out without being removed.
  void _paintLayer(Canvas canvas, GardenDocument document, String layerId) {
    final layer = document.layers[layerId]!;
    final geometry = document.geometryOf(layerId);
    // Red marks broken rules. Unfinished drawing also makes the layer
    // invalid (see Layers and Properties) but keeps its colour here, so
    // what is being drawn is not shown as a mistake.
    final invalid = document.ruleProblemOf(layerId) != null;
    final color = invalid ? Palette.invalid : layerColor(layer);
    final isSelected = layerId == scene.selectedLayerId;

    if (geometry.isClosed) {
      final path = _regionPath(geometry);
      if (invalid) {
        canvas.drawPath(
          path,
          Paint()..color = Palette.invalid.withValues(alpha: 0.08),
        );
      } else if (document.isActive(layerId)) {
        canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.07));
        _paintPattern(canvas, document, layerId, color);
      } else {
        _paintHatch(canvas, path);
      }
    }

    final width = scene.appearance.lineWidth + (isSelected ? 0.5 : 0);
    final stroke = Paint()
      ..color = color.withValues(alpha: isSelected ? 1 : 0.85)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final line in geometry.lines.values) {
      final path = curvePath(line.curve(geometry.points), _camera);
      if (invalid) {
        dashedPath(canvas, path, color, dash: 8, gap: 4, width: width);
      } else {
        canvas.drawPath(path, stroke);
      }
    }
    for (final circle in geometry.circles.values) {
      final centre = _camera.toScreen(geometry.points[circle.center]!);
      final radius = circle.radius * _camera.pixelsPerMetreNow;
      if (invalid) {
        _dashedCircle(canvas, centre, radius, color, width: width);
      } else {
        canvas.drawCircle(centre, radius, stroke);
      }
    }
    // Every piece of the layer carries its name, so land split across
    // several places reads as one group.
    for (final id in geometry.closedIds) {
      _paintLabel(canvas, layer, geometry, id);
    }
  }

  /// The layer's decorative pattern. Land of smaller layers (plots in a
  /// field, areas in a plot) is cut out, so a pattern never shows through
  /// under another. Invalid or inactive land shows its hatch instead (see
  /// [_paintLayer]).
  void _paintPattern(
    Canvas canvas,
    GardenDocument document,
    String layerId,
    Color color,
  ) {
    final pattern = document.patternOf(layerId);
    if (pattern == null) return;
    paintFillPattern(
      canvas,
      _patternArea(document, layerId).transform(cameraMatrix(_camera)),
      pattern,
      color.withValues(alpha: 0.45),
      _camera.toScreen(Vec.zero),
    );
  }

  /// The layer's land minus the land of smaller layers, in world metres.
  /// Cutting paths is slow, so it is done once per document, not per frame.
  Path _patternArea(GardenDocument document, String layerId) {
    final cache = _patternAreas[document] ??= {};
    return cache[layerId] ??= () {
      var area = worldRegionPath(document.geometryOf(layerId).region!);
      final depth = document.layers[layerId]!.kind.index;
      for (final otherId in document.drawingOrder) {
        if (document.layers[otherId]!.kind.index <= depth) continue;
        final land = document.geometryOf(otherId).region;
        if (land == null) continue;
        area = Path.combine(
          PathOperation.difference,
          area,
          worldRegionPath(land),
        );
      }
      return area;
    }();
  }

  /// Light grey diagonal lines marking a closed layer that is not active.
  void _paintHatch(Canvas canvas, Path region) {
    final bounds = region.getBounds();
    canvas.save();
    canvas.clipPath(region);
    final visible = visibleRect(canvas, bounds);
    if (visible != null) {
      canvas.drawRect(
        visible,
        Paint()..color = Palette.hatch.withValues(alpha: 0.12),
      );
      // Only the on-screen part is hatched, keeping the lines' spacing
      // tied to the shape's corner so they do not shift as the view moves.
      final lines = LineBatch();
      risingDiagonals(lines, visible, bounds.left + bounds.top, 8);
      lines.draw(
        canvas,
        Paint()
          ..color = Palette.hatch
          ..strokeWidth = 1,
      );
    }
    canvas.restore();
  }

  void _paintLabel(
    Canvas canvas,
    Layer layer,
    Geometry geometry,
    String shapeId,
  ) {
    final region = _regionPath(geometry, id: shapeId);
    final bounds = region.getBounds();
    if (!canvas.getLocalClipBounds().overlaps(bounds)) return;
    final style = switch (layer.kind) {
      LayerKind.field => const TextStyle(
        fontSize: 15,
        letterSpacing: 2,
        fontWeight: FontWeight.w600,
      ),
      LayerKind.plot => const TextStyle(fontSize: 13, letterSpacing: 1),
      LayerKind.area => const TextStyle(fontSize: 14),
    };
    final text = layer.kind == LayerKind.area
        ? layer.name
        : layer.name.toUpperCase();
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(color: const Color(0xFF3F5039)),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, bounds.width - 8));
    if (painter.width < 12 || painter.height > bounds.height - 4) return;
    // Fields label their top-left corner, clear of the plots inside. A
    // circular field has no corner, so its label sits in the upper part of
    // the circle (where the chord is still 80% of the width). Other circles
    // label just below their centre point, leaving the point visible.
    final isCircle = geometry.circles.containsKey(shapeId);
    final anchor = switch ((layer.kind, isCircle)) {
      (LayerKind.field, false) => Offset(bounds.left + 10, bounds.top + 8),
      (LayerKind.field, true) => Offset(
        bounds.center.dx - painter.width / 2,
        bounds.center.dy - bounds.height * 0.3 - painter.height / 2,
      ),
      (_, true) => bounds.center + Offset(-painter.width / 2, 10),
      _ => bounds.center - Offset(painter.width / 2, painter.height / 2),
    };
    final labelBox = anchor & Size(painter.width, painter.height);
    if (!region.contains(labelBox.center) ||
        !region.contains(labelBox.topLeft) ||
        !region.contains(labelBox.bottomRight)) {
      return;
    }
    canvas.save();
    canvas.clipPath(region);
    painter.paint(canvas, anchor);
    canvas.restore();
  }

  // -------------------------------------------------------- selected layer

  /// Point markers and selection highlights for the layer being edited.
  void _paintSelectedLayerDetail(
    Canvas canvas,
    Geometry geometry,
    MovePreview? move,
  ) {
    final highlight = Paint()
      ..color = Palette.accent.withValues(alpha: 0.35)
      ..strokeWidth = scene.appearance.lineWidth + 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final id in scene.selection) {
      if ((geometry.shapes.containsKey(id) ||
              geometry.circles.containsKey(id)) &&
          geometry.regionOf(id) != null) {
        final region = _regionPath(geometry, id: id);
        canvas.drawPath(
          region,
          Paint()..color = Palette.accent.withValues(alpha: 0.12),
        );
        canvas.drawPath(region, highlight);
      }
      final line = geometry.lines[id];
      if (line != null) {
        canvas.drawPath(
          curvePath(line.curve(geometry.points), _camera),
          highlight,
        );
      }
    }

    const radius = PointerReach.pointDiameter / 2;
    for (final entry in geometry.points.entries) {
      final centre = _camera.toScreen(entry.value);
      final selected = scene.selection.contains(entry.key);
      if (selected) {
        canvas.drawCircle(
          centre,
          radius + 4,
          Paint()..color = Palette.accent.withValues(alpha: 0.3),
        );
      }
      canvas.drawCircle(centre, radius, Paint()..color = Palette.paper);
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..color = selected ? Palette.accent : Palette.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    for (final id in [scene.lineAnchor, scene.joinStart]) {
      final point = geometry.points[id];
      if (point != null) {
        canvas.drawCircle(
          _camera.toScreen(point),
          radius,
          Paint()..color = Palette.accent,
        );
      }
    }
  }

  /// Dots the lines being dragged: green if releasing here keeps every
  /// layer valid, red if it would leave something invalid.
  void _paintMovedLines(
    Canvas canvas,
    GardenDocument document,
    MovePreview move,
  ) {
    final colour = move.valid ? Palette.valid : Palette.invalid;
    move.moved.forEach((layerId, points) {
      if (!document.layers.containsKey(layerId)) return;
      final geometry = document.geometryOf(layerId);
      for (final circle in geometry.circles.values) {
        if (points.contains(circle.center)) {
          _dashedCircle(
            canvas,
            _camera.toScreen(geometry.points[circle.center]!),
            circle.radius * _camera.pixelsPerMetreNow,
            colour,
            width: scene.appearance.lineWidth + 1,
            dash: 3,
            gap: 3,
          );
        }
      }
      for (final line in geometry.lines.values) {
        if (points.contains(line.start) || points.contains(line.end)) {
          dashedPath(
            canvas,
            curvePath(line.curve(geometry.points), _camera),
            colour,
            dash: 3,
            gap: 3,
            width: scene.appearance.lineWidth + 1,
          );
        }
      }
    });
  }

  // ---------------------------------------------------------------- previews

  void _paintPreview(Canvas canvas, Size size) {
    final preview = scene.preview;
    if (preview == null) return;
    _paintGuides(canvas, size, preview);
    final hoverLayer = preview is HoverPreview ? preview.layerId : null;
    final layerId = hoverLayer ?? scene.selectedLayerId;
    final geometry =
        layerId == null || !scene.document.layers.containsKey(layerId)
        ? null
        : scene.document.geometryOf(layerId);

    switch (preview) {
      case PointPreview(:final position, :final valid):
        final colour = valid ? Palette.valid : Palette.invalid;
        final centre = _camera.toScreen(position);
        canvas.drawCircle(
          centre,
          4,
          Paint()..color = colour.withValues(alpha: 0.35),
        );
        canvas.drawCircle(
          centre,
          4,
          Paint()
            ..color = colour
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      case SegmentPreview(
        :final from,
        :final to,
        :final valid,
        :final joinTarget,
      ):
        final colour = valid ? Palette.accent : Palette.invalid;
        _dashedLine(
          canvas,
          _camera.toScreen(from),
          _camera.toScreen(to),
          colour,
          dash: 7,
          gap: 5,
          width: scene.appearance.lineWidth,
        );
        if (joinTarget != null) _joinRing(canvas, _camera.toScreen(to), valid);
      case HoverPreview(:final itemId, :final destructive, :final joinable):
        if (geometry == null) return;
        final colour = destructive ? Palette.invalid : Palette.accent;
        final point = geometry.points[itemId];
        final line = geometry.lines[itemId];
        final circle = geometry.circles[itemId];
        if (circle != null && !joinable) {
          // A circle is both an edge and a region; show both.
          canvas.drawPath(
            _circlePath(geometry, circle),
            Paint()..color = colour.withValues(alpha: 0.10),
          );
          canvas.drawPath(
            _circlePath(geometry, circle),
            Paint()
              ..color = colour.withValues(alpha: 0.6)
              ..strokeWidth = scene.appearance.lineWidth + 4
              ..style = PaintingStyle.stroke,
          );
        } else if (point != null && joinable) {
          _joinRing(canvas, _camera.toScreen(point), true);
        } else if (point != null) {
          canvas.drawCircle(
            _camera.toScreen(point),
            PointerReach.pointDiameter / 2 + 3,
            Paint()
              ..color = colour
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        } else if (line != null) {
          canvas.drawPath(
            curvePath(line.curve(geometry.points), _camera),
            Paint()
              ..color = colour.withValues(alpha: 0.6)
              ..strokeWidth = scene.appearance.lineWidth + 4
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round,
          );
        } else if (geometry.regionOf(itemId) != null) {
          canvas.drawPath(
            _regionPath(geometry, id: itemId),
            Paint()..color = colour.withValues(alpha: 0.10),
          );
        }
      case CirclePreview(
        :final start,
        :final edge,
        :final centre,
        :final radius,
        :final valid,
      ):
        final colour = valid ? Palette.accent : Palette.invalid;
        final c = _camera.toScreen(centre);
        _dashedCircle(
          canvas,
          c,
          radius * _camera.pixelsPerMetreNow,
          colour,
          width: scene.appearance.lineWidth,
          dash: 7,
          gap: 5,
        );
        final from = _camera.toScreen(start);
        _dashedLine(
          canvas,
          from,
          _camera.toScreen(edge),
          colour,
          dash: 2,
          gap: 3,
          width: 1,
        );
        for (final marker in [from, c]) {
          canvas.drawCircle(marker, 3, Paint()..color = colour);
        }
        _paintCircleSize(canvas, c, radius, colour);
      case ArcPreview():
        _paintArcFeedback(canvas, preview);
      case PolygonPreview():
        _paintPolygonFeedback(canvas, preview);
      case BooleanPreview():
        _paintBooleanFeedback(canvas, preview);
      case ReferenceLinePreview(:final from, :final to, :final valid):
        _paintReferenceLine(
          canvas,
          from,
          to,
          valid ? const Color(0xFF376B95) : Palette.invalid,
          dashed: true,
        );
      case MovePreview() || ReferencePreview():
        break;
    }
  }

  /// The outer ring shown when a click would reuse an existing point.
  void _joinRing(Canvas canvas, Offset centre, bool valid) {
    canvas.drawCircle(
      centre,
      PointerReach.point + 2,
      Paint()
        ..color = valid ? Palette.accent : Palette.invalid
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _paintGuides(Canvas canvas, Size size, Preview preview) {
    const colour = Color(0xFF376B95);
    if (preview.guideX case final x?) {
      final sx = _camera.toScreen(Vec(x, 0)).dx;
      _dashedLine(
        canvas,
        Offset(sx, 0),
        Offset(sx, size.height),
        colour,
        dash: 2,
        gap: 4,
        width: 1,
      );
    }
    if (preview.guideY case final y?) {
      final sy = _camera.toScreen(Vec(0, y)).dy;
      _dashedLine(
        canvas,
        Offset(0, sy),
        Offset(size.width, sy),
        colour,
        dash: 2,
        gap: 4,
        width: 1,
      );
    }
  }

  // ----------------------------------------------------------------- helpers

  Path _circlePath(Geometry geometry, Circle circle) =>
      _regionPath(geometry, id: circle.id);

  /// The same contour path handles straight edges, arcs, circles and holes.
  Path _regionPath(Geometry geometry, {String? id}) {
    final region = id == null ? geometry.region : geometry.regionOf(id);
    return region == null ? Path() : regionPath(region, _camera);
  }

  /// The diameter of a circle being drawn, in the user's units, next to
  /// its centre.
  void _paintCircleSize(
    Canvas canvas,
    Offset centre,
    double radius,
    Color colour,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: '⌀ ${scene.units.format(radius * 2)}',
        style: TextStyle(
          fontSize: 12,
          color: colour,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = centre + const Offset(8, 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (at - const Offset(4, 2)) & Size(painter.width + 8, painter.height + 4),
        const Radius.circular(4),
      ),
      Paint()..color = Palette.paper.withValues(alpha: 0.9),
    );
    painter.paint(canvas, at);
  }

  void _dashedCircle(
    Canvas canvas,
    Offset centre,
    double radius,
    Color colour, {
    required double width,
    double dash = 8,
    double gap = 4,
  }) {
    if (radius <= 0) return;
    final rect = Rect.fromCircle(center: centre, radius: radius);
    final circumference = 2 * math.pi * radius;
    final steps = math.max(1, (circumference / (dash + gap)).floor());
    final sweep = 2 * math.pi / steps;
    final dashSweep = sweep * dash / (dash + gap);
    // Dashes wholly off screen are skipped; the rest go in one path. No
    // part of a dash is farther from its start than its arc length.
    final reach = canvas.getLocalClipBounds().inflate(
      dashSweep * radius + width,
    );
    if (!reach.overlaps(rect)) return;
    final dashes = Path();
    for (var i = 0; i < steps; i++) {
      final angle = i * sweep;
      final start = centre + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (!reach.contains(start)) continue;
      dashes.addArc(rect, angle, dashSweep);
    }
    canvas.drawPath(
      dashes,
      Paint()
        ..color = colour
        ..strokeWidth = width
        ..style = PaintingStyle.stroke,
    );
  }

  void _dashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Color colour, {
    required double dash,
    required double gap,
    required double width,
  }) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt;
    final length = (to - from).distance;
    if (length == 0) return;
    final step = (to - from) / length;
    for (var d = 0.0; d < length; d += dash + gap) {
      canvas.drawLine(
        from + step * d,
        from + step * math.min(d + dash, length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(ScenePainter oldDelegate) => true;
}

/// Each document's pattern areas by layer, in world metres. Documents are
/// immutable, so an entry stays right for as long as its document lives.
final _patternAreas = Expando<Map<String, Path>>('pattern areas');

/// The outline colour used for a layer on the canvas and in Layers.
Color layerColor(Layer layer) => switch (layer.properties) {
  FieldProperties p => Color(p.color.argb),
  PlotProperties p => Color(p.color.argb),
  AreaProperties() => Palette.area,
};
