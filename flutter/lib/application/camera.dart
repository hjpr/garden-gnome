import 'dart:math' as math;
import 'dart:ui';

import '../domain/units.dart';
import '../domain/vec.dart';

/// Logical screen pixels per metre with the camera at [Camera.startHeight].
const double pixelsPerMetre = 30;

/// Wheel steps needed to halve the camera's height, doubling the scale.
const int zoomStepsPerDoubling = 4;

/// A virtual camera looking straight down at the drawing.
///
/// [height] is how far above the ground the camera is, in metres. As with a
/// real lens, the ground looks twice as large from half the height.
///
/// [topLeft] is the world position at the viewport's top-left corner. Every
/// conversion between screen and world positions goes through this class so
/// painting, hit testing, and snapping always agree.
class Camera {
  const Camera({this.topLeft = Vec.zero, this.height = startHeight});

  /// Where a new view starts: 100 ft up.
  static const double startHeight = 100 * _metresPerFoot;

  final Vec topLeft;
  final double height;

  double get pixelsPerMetreNow => pixelsPerMetre * (startHeight / height);

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
    height: height,
  );

  /// Zooms by whole wheel [steps], keeping the world point under [anchor]
  /// in place. Positive steps lower the camera, zooming in.
  Camera zoomAt(Offset anchor, int steps, {required HeightLimits limits}) =>
      atHeight(
        limits.clamp(height * math.pow(2, -steps / zoomStepsPerDoubling)),
        anchor: anchor,
      );

  /// Moves the camera to [newHeight], keeping the world point under
  /// [anchor] in place.
  Camera atHeight(double newHeight, {required Offset anchor}) {
    final fixed = toWorld(anchor);
    final moved = Camera(topLeft: topLeft, height: newHeight);
    final offset = Vec(anchor.dx, anchor.dy) / moved.pixelsPerMetreNow;
    return Camera(topLeft: fixed - offset, height: newHeight);
  }

  /// The camera height at which [metres] of ground spans [pixels].
  static double heightFor({required double metres, required double pixels}) =>
      startHeight * pixelsPerMetre * metres / pixels;

  /// Keeps the previous world centre when the viewport changes size.
  Camera resized(Size from, Size to) {
    final centre = toWorld(Offset(from.width / 2, from.height / 2));
    final half = Vec(to.width / 2, to.height / 2) / pixelsPerMetreNow;
    return Camera(topLeft: centre - half, height: height);
  }

  /// Side length of one grid cell in metres.
  ///
  /// The cell is a round length in the [units] shown (0.5, 1, 5, 10, 20 ft
  /// and so on), so snapped points land on numbers a grower would measure
  /// out. It is the smallest such length at least [minGridCellPixels]
  /// across on screen. Grid lines are anchored to the origin.
  double gridCellMetres(Units units) {
    final steps = gridSteps[units]!;
    for (final step in steps) {
      final metres = units.toMetres(step);
      if (metres * pixelsPerMetreNow >= minGridCellPixels) return metres;
    }
    return units.toMetres(steps.last);
  }
}

/// The smallest a grid cell may look on screen, in logical pixels.
const double minGridCellPixels = 24;

/// The grid sizes offered in each unit, smallest first.
const Map<Units, List<double>> gridSteps = {
  Units.feet: [0.5, 1, 5, 10, 20, 50, 100],
  Units.metres: [0.1, 0.5, 1, 2, 5, 10, 20, 50],
};

/// How low and how high the camera may go, in metres. A small plot wants
/// a lower camera; a large property wants a higher one.
class HeightLimits {
  const HeightLimits({
    this.lowest = 5 * _metresPerFoot,
    this.highest = 500 * _metresPerFoot,
  });

  final double lowest;
  final double highest;

  double clamp(double height) => height.clamp(lowest, highest);
}

const double _metresPerFoot = 0.3048;
