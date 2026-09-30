import 'package:flutter/material.dart';

import '../../application/camera.dart';
import '../../application/hit_testing.dart';
import '../../application/previews.dart';
import '../../domain/document.dart';
import '../../domain/geometry.dart';
import '../../domain/land_rules.dart';
import '../../domain/row_layout.dart';
import '../../domain/zone_ground.dart';
import '../theme.dart';
import 'curve_paths.dart';
import 'pattern_painter.dart';
import 'scene_state.dart';

class LandPainter {
  const LandPainter(this.scene);

  final SceneState scene;

  Camera get _camera => scene.camera;

  /// Active land gets a light fill. Closed land that is not active is
  /// hatched. Invalid land is drawn in red with dashed lines, so it stands
  /// out without being removed.
  ///
  /// [outlineOnly] draws just the outline, as the Render view does for the
  /// selected layer over its textures.
  void paintLayer(
    Canvas canvas,
    GardenDocument document,
    String layerId, {
    bool outlineOnly = false,
  }) {
    final layer = document.layers[layerId]!;
    final geometry = document.geometryOf(layerId);
    // Red marks broken rules. Unfinished drawing also makes the layer
    // invalid (see Layers and Properties) but keeps its colour here, so
    // what is being drawn is not shown as a mistake.
    final invalid = document.ruleProblemOf(layerId) != null;
    final color = invalid ? Palette.invalid : layerColor(layer);
    final isSelected = layerId == scene.selectedLayerId;

    if (geometry.isClosed && !outlineOnly) {
      final path = _regionPath(geometry);
      if (invalid) {
        canvas.drawPath(
          path,
          Paint()..color = Palette.invalid.withValues(alpha: 0.08),
        );
      } else if (document.isActive(layerId)) {
        canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.07));
        _paintWireRows(canvas, document, layerId);
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
      final path = linePath(line, geometry.points, _camera);
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
        paintDashedCircle(canvas, centre, radius, color, width: width);
      } else {
        canvas.drawCircle(centre, radius, stroke);
      }
    }
    // Shapes carry no name on the canvas: Properties and the status bar
    // say what is selected, and colour tells layers apart.
  }

  /// Light grey diagonal lines marking a closed layer that is not active.
  void _paintHatch(Canvas canvas, Path region) {
    canvas.drawPath(
      region,
      Paint()..color = Palette.hatch.withValues(alpha: 0.12),
    );
    // The lines are tied to the shape's corner, so they move with it.
    paintHatch(
      canvas,
      region,
      Palette.hatch,
      8,
      region.getBounds().topLeft,
      devicePixelRatio: scene.devicePixelRatio,
    );
  }

  /// Point markers and selection highlights for the layer being edited.
  void paintSelectedLayerDetail(Canvas canvas, Geometry geometry) {
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
        canvas.drawPath(linePath(line, geometry.points, _camera), highlight);
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

    for (final id in [scene.lineAnchor]) {
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
  void paintMovedLines(
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
          paintDashedCircle(
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
            linePath(line, geometry.points, _camera),
            colour,
            dash: 3,
            gap: 3,
            width: scene.appearance.lineWidth + 1,
          );
        }
      }
    });
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

  /// The same contour path handles straight edges, arcs, circles and holes.
  Path _regionPath(Geometry geometry, {String? id}) {
    final region = id == null ? geometry.region : geometry.regionOf(id);
    return region == null ? Path() : regionPath(region, _camera);
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
