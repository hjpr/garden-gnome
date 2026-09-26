import 'dart:math' as math;
import 'dart:ui';

import '../domain/vec.dart';

/// Logical screen pixels per metre at 100% zoom.
const double pixelsPerMetre = 30;

/// Wheel steps needed to double the zoom.
const int zoomStepsPerDoubling = 4;

/// The part of the world shown in the drawing viewport.
///
/// [topLeft] is the world position at the viewport's top-left corner. Every
/// conversion between screen and world positions goes through this class so
/// painting, hit testing, and snapping always agree.
class Camera {
  const Camera({this.topLeft = Vec.zero, this.zoom = 1});

  final Vec topLeft;
  final double zoom;

  double get pixelsPerMetreNow => pixelsPerMetre * zoom;

  Offset toScreen(Vec world) {
    final p = (world - topLeft) * pixelsPerMetreNow;
    return Offset(p.x, p.y);
  }

  Vec toWorld(Offset screen) =>
      topLeft + Vec(screen.dx, screen.dy) / pixelsPerMetreNow;

  /// Converts a screen distance to metres.
  double metres(double pixels) => pixels / pixelsPerMetreNow;

  Camera panBy(Offset screenDelta) => Camera(
    topLeft: topLeft - Vec(screenDelta.dx, screenDelta.dy) / pixelsPerMetreNow,
    zoom: zoom,
  );

  /// Zooms by whole wheel [steps], keeping the world point under [anchor]
  /// in place. Positive steps zoom in.
  Camera zoomAt(Offset anchor, int steps, {required ZoomLimits limits}) {
    final target = limits.clamp(
      zoom * math.pow(2, steps / zoomStepsPerDoubling).toDouble(),
    );
    return zoomTo(target, anchor: anchor);
  }

  Camera zoomTo(double newZoom, {required Offset anchor}) {
    final fixed = toWorld(anchor);
    final offset = Vec(anchor.dx, anchor.dy) / (pixelsPerMetre * newZoom);
    return Camera(topLeft: fixed - offset, zoom: newZoom);
  }

  /// Keeps the previous world centre when the viewport changes size.
  Camera resized(Size from, Size to) {
    final centre = toWorld(Offset(from.width / 2, from.height / 2));
    final half = Vec(to.width / 2, to.height / 2) / pixelsPerMetreNow;
    return Camera(topLeft: centre - half, zoom: zoom);
  }

  /// Side length of one grid cell in metres.
  ///
  /// Cells stay between 30 and 60 screen pixels: each doubling of zoom halves
  /// the distance a cell represents. Grid lines are anchored to the origin.
  double get gridCellMetres => math.pow(2, -_log2(zoom).floor()).toDouble();

  static double _log2(double value) => math.log(value) / math.ln2 + 1e-9;
}

class ZoomLimits {
  const ZoomLimits({this.min = 0.25, this.max = 8});

  final double min;
  final double max;

  double clamp(double zoom) => zoom.clamp(min, max);
}
