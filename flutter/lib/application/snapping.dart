import '../domain/geometry.dart';
import '../domain/vec.dart';
import 'camera.dart';

/// How far, in logical pixels, a position is pulled onto a guide line.
const double alignmentReach = 6;

/// How far, in logical pixels, a position is pulled onto a guide target
/// (a line's midpoint, a circle's outermost point). Wider than
/// [alignmentReach], because landing on that spot is the whole aim.
const double targetReach = 10;

/// A path positions can be pulled onto while lining up.
sealed class Guide {
  const Guide();

  /// How far [p] is from the guide, in metres.
  double distanceTo(Vec p);

  /// The nearest place on the guide to [p].
  Vec project(Vec p);
}

/// An endless straight guide through [through] along unit [direction].
class GuideLine extends Guide {
  const GuideLine(this.through, this.direction);

  /// A guide through [through] parallel to [along], or null if [along]
  /// has no length.
  static GuideLine? along(Vec through, Vec along) {
    final length = along.length;
    return length == 0 ? null : GuideLine(through, along / length);
  }

  final Vec through;
  final Vec direction;

  Vec get normal => Vec(-direction.y, direction.x);
  bool get isHorizontal => direction.y == 0;
  bool get isVertical => direction.x == 0;

  @override
  double distanceTo(Vec p) => normal.dot(p - through).abs();

  @override
  Vec project(Vec p) => through + direction * direction.dot(p - through);
}

/// A circular guide: the whole circle an arc belongs to.
class GuideCircle extends Guide {
  const GuideCircle(this.centre, this.radius);

  final Vec centre;
  final double radius;

  @override
  double distanceTo(Vec p) => (p.distanceTo(centre) - radius).abs();

  @override
  Vec project(Vec p) {
    final away = p - centre;
    final length = away.length;
    if (length == 0) return centre + Vec(radius, 0);
    return centre + away * (radius / length);
  }
}

/// What a hovered item offers to line up with.
class GuideSet {
  const GuideSet({
    this.targets = const [],
    this.guides = const [],
    this.markers = const [],
  });

  static const empty = GuideSet();

  /// Spots positions land on, within [targetReach].
  final List<Vec> targets;

  /// Paths positions are pulled onto, within [alignmentReach].
  final List<Guide> guides;

  /// Where the canvas marks the guide source.
  final List<Vec> markers;

  bool get isEmpty => targets.isEmpty && guides.isEmpty;
}

/// What a snap lined up with, for drawing it.
class SnapGuides {
  const SnapGuides({this.lines = const [], this.mark});

  static const none = SnapGuides();

  /// The guides in use, drawn dashed across the view.
  final List<Guide> lines;

  /// A target landed on, marked with a ring.
  final Vec? mark;

  bool get isEmpty => lines.isEmpty && mark == null;
}

/// A snapped position and the guides that produced it.
class SnapResult {
  const SnapResult(this.position, {this.guides = SnapGuides.none});

  final Vec position;
  final SnapGuides guides;
}

/// A shift that lines moving handles up with guides.
///
/// [freeX] and [freeY] name the axes the guides leave open for the grid
/// to place: a horizontal guide fixes only y and a vertical one only x.
/// Any other guide, or a target, fixes both.
class GuideFit {
  const GuideFit({
    this.shift = Vec.zero,
    this.freeX = true,
    this.freeY = true,
    this.guides = SnapGuides.none,
  });

  static const none = GuideFit();

  final Vec shift;
  final bool freeX;
  final bool freeY;
  final SnapGuides guides;
}

/// Moves [position] to the nearest visible grid intersection.
SnapResult snapToGrid(Vec position, Camera camera) {
  final cell = camera.gridCellMetres;
  double nearest(double value) => (value / cell).round() * cell;
  return SnapResult(Vec(nearest(position.x), nearest(position.y)));
}

/// Finds the shift that lines one of [handles] up with [set].
///
/// In order of preference:
/// 1. A handle near a target lands on it.
/// 2. A handle near a guide is pulled onto it. For a straight guide, if a
///    handle is then also near a second guide line crossing it, the shift
///    puts both handles on their guides at once.
/// Ties go to the handle and guide listed first.
GuideFit fitToGuides(List<Vec> handles, GuideSet set, Camera camera) {
  if (handles.isEmpty || set.isEmpty) return GuideFit.none;

  final targetGapMax = camera.metres(targetReach);
  Vec? target;
  var targetShift = Vec.zero;
  var targetGap = targetGapMax;
  for (final t in set.targets) {
    for (final h in handles) {
      final gap = t.distanceTo(h);
      if (gap <= targetGap && (target == null || gap < targetGap)) {
        target = t;
        targetShift = t - h;
        targetGap = gap;
      }
    }
  }
  if (target != null) {
    return GuideFit(
      shift: targetShift,
      freeX: false,
      freeY: false,
      guides: SnapGuides(mark: target),
    );
  }

  final reach = camera.metres(alignmentReach);
  Guide? first;
  var firstHandle = Vec.zero;
  var firstGap = reach;
  for (final g in set.guides) {
    for (final h in handles) {
      final gap = g.distanceTo(h);
      if (gap <= firstGap && (first == null || gap < firstGap)) {
        first = g;
        firstHandle = h;
        firstGap = gap;
      }
    }
  }
  if (first == null) return GuideFit.none;
  final shift = first.project(firstHandle) - firstHandle;
  if (first is GuideLine) {
    final both = _alsoOnCrossingLine(
      first,
      firstHandle,
      shift,
      handles,
      set,
      reach,
    );
    if (both != null) return both;
    return GuideFit(
      shift: shift,
      freeX: first.isHorizontal,
      freeY: first.isVertical,
      guides: SnapGuides(lines: [first]),
    );
  }
  return GuideFit(
    shift: shift,
    freeX: false,
    freeY: false,
    guides: SnapGuides(lines: [first]),
  );
}

/// With [shift] putting [handle] on [first], looks for a handle near a
/// second guide line that crosses [first], and returns the shift that
/// puts both handles on their guides.
GuideFit? _alsoOnCrossingLine(
  GuideLine first,
  Vec handle,
  Vec shift,
  List<Vec> handles,
  GuideSet set,
  double reach,
) {
  GuideLine? second;
  var secondHandle = Vec.zero;
  var secondGap = double.infinity;
  for (final g in set.guides) {
    if (g is! GuideLine || identical(g, first)) continue;
    if (first.direction.cross(g.direction).abs() < 1e-9) continue;
    for (final h in handles) {
      final gap = g.distanceTo(h + shift);
      if (gap < secondGap) {
        second = g;
        secondHandle = h;
        secondGap = gap;
      }
    }
  }
  if (second == null) return null;
  final n1 = first.normal;
  final n2 = second.normal;
  // Each guide is lined up along its own normal: n·(h + s) = n·through.
  final c1 = n1.dot(first.through - handle);
  final c2 = n2.dot(second.through - secondHandle);
  final det = n1.x * n2.y - n1.y * n2.x;
  final solved = Vec(
    (c1 * n2.y - n1.y * c2) / det,
    (n1.x * c2 - c1 * n2.x) / det,
  );
  // Accept only when reaching the second guide moves the handles no
  // farther than the first pull may.
  return (solved - shift).length <= reach
      ? GuideFit(
          shift: solved,
          freeX: false,
          freeY: false,
          guides: SnapGuides(lines: [first, second]),
        )
      : null;
}

/// Lines a single [position] up with [set]. An axis the guides leave
/// open keeps [fallback]'s value (the grid position, or the pointer).
SnapResult snapToGuides(
  Vec position,
  Camera camera,
  GuideSet set, {
  Vec? fallback,
}) {
  final base = fallback ?? position;
  final fit = fitToGuides([position], set, camera);
  final moved = position + fit.shift;
  return SnapResult(
    Vec(fit.freeX ? base.x : moved.x, fit.freeY ? base.y : moved.y),
    guides: fit.guides,
  );
}

/// The four outermost points of a circle: left, right, top and bottom.
List<Vec> circleExtremes(Vec centre, double radius) => [
  centre + Vec(-radius, 0),
  centre + Vec(radius, 0),
  centre + Vec(0, -radius),
  centre + Vec(0, radius),
];

/// What a hovered item offers to line up with.
///
/// - A point: its horizontal and vertical.
/// - A line: its midpoint as a target, its own path (carried on past
///   both ends; for an arc, the arc's whole circle), and the
///   perpendicular through its midpoint.
/// - A circle: its leftmost, rightmost, top and bottom points as targets.
/// Whole shapes offer nothing; their points and lines are hovered instead.
GuideSet guidesOf(Geometry geometry, String itemId) {
  if (geometry.points[itemId] case final p?) {
    return GuideSet(
      guides: [GuideLine(p, const Vec(1, 0)), GuideLine(p, const Vec(0, 1))],
      markers: [p],
    );
  }
  if (geometry.lines[itemId] case final line?) {
    // A Bézier curve offers its middle and the line square to it there.
    if (line.bezier(geometry.points) case final bezier?) {
      final mid = bezier.pointAt(0.5);
      final along = bezier.tangentAt(0.5);
      return GuideSet(
        targets: [mid],
        guides: [
          if (along != Vec.zero) ?GuideLine.along(mid, Vec(-along.y, along.x)),
        ],
        markers: [mid],
      );
    }
    final curve = line.curve(geometry.points);
    final mid = curve.pointAt(0.5);
    if (curve.start == curve.end) {
      return GuideSet(targets: [mid], markers: [mid]);
    }
    final Guide? path;
    final GuideLine? across;
    if (curve.isArc) {
      path = GuideCircle(curve.centre, curve.radius);
      across = GuideLine.along(mid, mid - curve.centre);
    } else {
      final chord = curve.end - curve.start;
      path = GuideLine.along(curve.start, chord);
      across = GuideLine.along(mid, Vec(-chord.y, chord.x));
    }
    return GuideSet(targets: [mid], guides: [?path, ?across], markers: [mid]);
  }
  if (geometry.circles[itemId] case final circle?) {
    final extremes = circleExtremes(
      geometry.points[circle.center]!,
      circle.radius,
    );
    return GuideSet(targets: extremes, markers: extremes);
  }
  return GuideSet.empty;
}
