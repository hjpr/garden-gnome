import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../application/camera.dart';
import '../../application/curve_handles.dart';
import '../../application/hit_testing.dart';
import '../../application/previews.dart';
import '../../application/snapping.dart';
import '../../application/transform_box.dart';
import '../../application/workspace_settings.dart';
import '../../domain/bezier.dart';
import '../../domain/document.dart';
import '../../domain/feature.dart';
import '../../domain/geometry.dart';
import '../../domain/layer.dart';
import '../../domain/plant_layout.dart';
import '../../domain/reference_image.dart';
import '../../domain/row_layout.dart';
import '../../domain/vec.dart';
import '../theme.dart';
import 'curve_paths.dart';
import 'land_painter.dart';
import 'measurement_label.dart';
import 'pattern_painter.dart';
import 'render_assets.dart';
import 'scene_state.dart';

part 'construction_painter.dart';
part 'feature_painter.dart';
part 'plant_painter.dart';
part 'reference_painter.dart';
part 'render_painter.dart';

/// Draws the grid, every layer, and the current tool feedback.
class ScenePainter extends CustomPainter {
  ScenePainter(this.scene);

  final SceneState scene;

  Camera get _camera => scene.camera;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    // While dragging, the drawing is shown as it would be if released now.
    final move = scene.preview is MovePreview
        ? scene.preview as MovePreview
        : null;
    final boolean = scene.preview is BooleanPreview
        ? scene.preview as BooleanPreview
        : null;
    final document = boolean?.document ?? move?.document ?? scene.document;
    final render = scene.viewMode == ViewMode.render;
    final land = LandPainter(scene);

    if (render) {
      // The farm from above. Reference pictures are for tracing, so they
      // stay out of it; outlines are drawn only for the selected layer.
      _paintRenderGround(canvas, size, document);
    } else {
      canvas.drawColor(Palette.canvas, BlendMode.src);
      _paintGrid(canvas, size);
      if (!scene.referenceHidden) _paintReference(canvas);
      for (final layerId in document.drawingOrder) {
        if (scene.shows(layerId)) land.paintLayer(canvas, document, layerId);
      }
    }
    // Plants sit on the ground, under raised beds and tunnels.
    _paintPlants(canvas, size, document);
    _paintGrowOutlines(canvas, document);
    _paintFeatures(canvas);
    if (render) {
      final selected = scene.selectedLayerId;
      if (selected != null &&
          document.layers.containsKey(selected) &&
          scene.shows(selected)) {
        land.paintLayer(canvas, document, selected, outlineOnly: true);
      }
    }

    final selectedId = scene.selectedLayerId;
    if (selectedId != null &&
        document.layers.containsKey(selectedId) &&
        scene.shows(selectedId)) {
      land.paintSelectedLayerDetail(canvas, document.geometryOf(selectedId));
      if (scene.showCurveHandles) {
        _paintCurveHandles(canvas, document.geometryOf(selectedId));
      }
    }
    if (move != null) land.paintMovedLines(canvas, document, move);
    if (scene.selectionBox case final box?) _paintSelectionBox(canvas, box);
    _paintPreview(canvas, size);
    _paintGuideAnchors(canvas);
  }

  /// The dashed box around the selection, with a handle dot at each
  /// corner and edge middle for scaling. Rotating grabs just outside a
  /// corner, so nothing extra is drawn for it.
  void _paintSelectionBox(Canvas canvas, TransformBox box) {
    final corners = box.screenCorners(_camera);
    final outline = Path()..addPolygon(corners, true);
    dashedPath(
      canvas,
      outline,
      Palette.accent.withValues(alpha: 0.8),
      width: 1,
      dash: 5,
      gap: 4,
    );
    final fill = Paint()..color = Palette.paper;
    final ring = Paint()
      ..color = Palette.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final handle in BoxHandle.values) {
      final at = box.screenPointOf(handle, _camera);
      canvas.drawCircle(at, BoxReach.handleRadius, fill);
      canvas.drawCircle(at, BoxReach.handleRadius, ring);
    }
  }

  // -------------------------------------------------------------------- grid

  void _paintGrid(Canvas canvas, Size size) {
    final a = scene.appearance;
    final paint = Paint()
      ..color = Color(a.gridColor).withValues(alpha: a.gridOpacity)
      ..strokeWidth = a.gridThickness;
    final cell = _camera.gridCellMetres(scene.units);
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
        _paintHighlight(
          canvas,
          geometry,
          itemId,
          destructive ? Palette.invalid : Palette.accent,
          joinable: joinable,
        );
      case AreaSelectPreview():
        _paintAreaSelect(canvas, preview);
      case CirclePreview(
        :final start,
        :final edge,
        :final centre,
        :final radius,
        :final valid,
      ):
        final colour = valid ? Palette.accent : Palette.invalid;
        final c = _camera.toScreen(centre);
        paintDashedCircle(
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
        paintMeasurementLabel(
          canvas,
          text: '⌀ ${scene.units.format(radius * 2)}',
          anchor: c,
          color: colour,
        );
      case ArcPreview():
        _paintArcFeedback(canvas, preview);
      case PolygonPreview():
        _paintPolygonFeedback(canvas, preview);
      case CurvePreview():
        _paintCurveFeedback(canvas, preview);
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
      case SeedDropPreview(:final layerId?):
        // The grow zone a dropped seed would be planted in.
        final region = scene.document.layers.containsKey(layerId)
            ? scene.document.geometryOf(layerId).region
            : null;
        if (region == null) return;
        final path = regionPath(region, _camera);
        canvas.drawPath(
          path,
          Paint()..color = Palette.accent.withValues(alpha: 0.18),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = Palette.accent
            ..strokeWidth = scene.appearance.lineWidth + 2
            ..style = PaintingStyle.stroke,
        );
      case SeedDropPreview() ||
          MovePreview() ||
          ReferencePreview() ||
          FeatureHoverPreview() ||
          FeatureMovePreview():
        // Drawn with the drawing itself, or by the feature painter.
        break;
    }
  }

  /// Marks one item as about to be picked: a point's ring, a line's glow,
  /// or a shape's tinted inside.
  void _paintHighlight(
    Canvas canvas,
    Geometry geometry,
    String itemId,
    Color colour, {
    bool joinable = false,
  }) {
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
        linePath(line, geometry.points, _camera),
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
  }

  /// The marquee rectangle or lasso outline, lightly tinted, with every
  /// item that letting go would select highlighted.
  void _paintAreaSelect(Canvas canvas, AreaSelectPreview preview) {
    if (preview.layerId case final layerId?
        when scene.document.layers.containsKey(layerId)) {
      final geometry = scene.document.geometryOf(layerId);
      for (final id in preview.items) {
        _paintHighlight(canvas, geometry, id, Palette.accent);
      }
    }
    final outline = Path()
      ..addPolygon([
        for (final p in preview.outline) _camera.toScreen(p),
      ], true);
    canvas.drawPath(
      outline,
      Paint()..color = Palette.accent.withValues(alpha: 0.06),
    );
    dashedPath(
      canvas,
      outline,
      Palette.accent.withValues(alpha: 0.9),
      width: 1,
      dash: 5,
      gap: 4,
    );
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

  static const _guideColour = Color(0xFF376B95);

  /// Four short diagonal ticks around each place guides come from, so
  /// the user sees what is lined up against before moving anything. They
  /// sit outside the point marker and hover ring so neither hides them.
  void _paintGuideAnchors(Canvas canvas) {
    if (scene.guideMarkers.isEmpty) return;
    final paint = Paint()
      ..color = _guideColour
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const inner = 8.0;
    const outer = 13.0;
    for (final marker in scene.guideMarkers) {
      final c = _camera.toScreen(marker);
      for (final d in const [
        Offset(1, 1),
        Offset(1, -1),
        Offset(-1, 1),
        Offset(-1, -1),
      ]) {
        final unit = d / d.distance;
        canvas.drawLine(c + unit * inner, c + unit * outer, paint);
      }
    }
  }

  /// Each guide in use drawn dashed across the view, and a ring on a
  /// target landed on.
  void _paintGuides(Canvas canvas, Size size, Preview preview) {
    final guides = preview.guides;
    for (final guide in guides.lines) {
      switch (guide) {
        case GuideLine():
          _paintGuideLine(canvas, size, guide);
        case GuideCircle(:final centre, :final radius):
          paintDashedCircle(
            canvas,
            _camera.toScreen(centre),
            radius * _camera.pixelsPerMetreNow,
            _guideColour,
            width: 1,
            dash: 4,
            gap: 4,
          );
      }
    }
    if (guides.mark case final mark?) {
      canvas.drawCircle(
        _camera.toScreen(mark),
        PointerReach.point,
        Paint()
          ..color = _guideColour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  /// A straight guide, clipped to the view: it runs through the view's
  /// centre projection, out as far as the view's diagonal each way.
  void _paintGuideLine(Canvas canvas, Size size, GuideLine guide) {
    final middle = guide.project(
      _camera.toWorld(Offset(size.width / 2, size.height / 2)),
    );
    final half = _camera.metres(size.longestSide * 1.5);
    _dashedLine(
      canvas,
      _camera.toScreen(middle - guide.direction * half),
      _camera.toScreen(middle + guide.direction * half),
      _guideColour,
      dash: 4,
      gap: 4,
      width: 1,
    );
  }

  // ----------------------------------------------------------------- helpers

  Path _circlePath(Geometry geometry, Circle circle) =>
      _regionPath(geometry, id: circle.id);

  /// The same contour path handles straight edges, arcs, circles and holes.
  Path _regionPath(Geometry geometry, {String? id}) {
    final region = id == null ? geometry.region : geometry.regionOf(id);
    return region == null ? Path() : regionPath(region, _camera);
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
