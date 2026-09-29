import 'dart:math' as math;

/// How a zone's soil is prepared. A zone with no ground set is plain,
/// tidy dirt.
enum GroundType {
  /// One level, prepared bed across the whole zone.
  flat('Flat'),

  /// Parallel planting rows with paths between them; see [RowSpec].
  row('Row');

  const GroundType(this.label);

  final String label;

  /// The type saved under [name], or null for none.
  static GroundType? fromName(String? name) =>
      name == null ? null : values.asNameMap()[name];
}

/// The size and heading of a zone's planting rows.
///
/// The rows are what planting and yield are counted along, and what the
/// Render view draws.
class RowSpec {
  const RowSpec({
    this.width = defaultWidth,
    this.spacing = defaultSpacing,
    this.direction = 0,
  });

  /// A 30 inch bed with an 18 inch path, a common market-garden layout.
  static const double defaultWidth = 0.762;
  static const double defaultSpacing = 0.4572;

  /// Width of one planted row, in metres.
  final double width;

  /// The path between two rows, edge to edge, in metres.
  final double spacing;

  /// Which way the rows run, in degrees clockwise from north (up the
  /// screen): 0 runs them north–south, 90 east–west. Kept in [0, 180),
  /// since a row pointing one way also points the opposite way.
  final double direction;

  /// Centre-to-centre distance between neighbouring rows.
  double get pitch => width + spacing;

  /// Why these values cannot be used, or null when they can.
  String? get problem {
    if (!(width > 0) || !width.isFinite) return 'Row width must be above 0';
    if (!(spacing >= 0) || !spacing.isFinite) {
      return 'Row spacing cannot be negative';
    }
    if (!direction.isFinite) return 'Enter a direction in degrees';
    return null;
  }

  /// [degrees] folded into [0, 180).
  static double normalDirection(double degrees) {
    final folded = degrees % 180;
    return folded < 0 ? folded + 180 : folded;
  }

  RowSpec copyWith({double? width, double? spacing, double? direction}) =>
      RowSpec(
        width: width ?? this.width,
        spacing: spacing ?? this.spacing,
        direction: direction == null
            ? this.direction
            : normalDirection(direction),
      );

  /// Unit vector along the rows, in world coordinates (y grows down the
  /// screen, so north is -y).
  (double, double) get along {
    final radians = direction * math.pi / 180;
    return (math.sin(radians), -math.cos(radians));
  }

  @override
  bool operator ==(Object other) =>
      other is RowSpec &&
      other.width == width &&
      other.spacing == spacing &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(width, spacing, direction);
}
