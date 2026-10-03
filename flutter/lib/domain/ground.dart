import 'dart:math' as math;

/// How a bed's soil is prepared. A bed with no ground set is fallow:
/// unprepared dirt that nothing is planted on. [grow] marks a planting
/// rather than soil.
enum GroundType {
  /// One level, prepared bed across the whole zone.
  flat('Flat'),

  /// Parallel planting rows with paths between them; see [RowSpec].
  row('Row'),

  /// A grow zone: not soil of its own, but an area drawn over Flat or Row
  /// ground to say what is planted there. Seeds are dropped on it in
  /// Build's Plant mode, and plants follow the ground underneath.
  grow('Grow');

  const GroundType(this.label);

  final String label;

  /// Whether this is soil of its own (Flat, Row) that grow zones plant on.
  bool get isSoil => this != grow;

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
    this.border = 0,
  });

  /// A 30 inch bed with an 18 inch path, a common market-garden layout.
  static const double defaultWidth = 0.762;
  static const double defaultSpacing = 0.4572;

  /// Width of one planted row, in metres.
  final double width;

  /// The path between two rows, edge to edge, in metres.
  final double spacing;

  /// Clear distance from the zone boundary to the planted strips, in metres.
  /// Includes the rims of holes; zero preserves edge-to-edge layouts.
  final double border;

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
    if (!(border >= 0) || !border.isFinite) {
      return 'Row border must be a finite distance of 0 or more';
    }
    if (!direction.isFinite) return 'Enter a direction in degrees';
    return null;
  }

  /// [degrees] folded into [0, 180).
  static double normalDirection(double degrees) {
    final folded = degrees % 180;
    return folded < 0 ? folded + 180 : folded;
  }

  RowSpec copyWith({
    double? width,
    double? spacing,
    double? direction,
    double? border,
  }) => RowSpec(
    width: width ?? this.width,
    spacing: spacing ?? this.spacing,
    border: border ?? this.border,
    direction: direction == null ? this.direction : normalDirection(direction),
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
      other.border == border &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(width, spacing, direction, border);
}

/// The seed planted in a grow zone: which Seed Vault variety, and how far
/// apart its plants go.
///
/// The name is kept with the drawing so it still reads correctly if the
/// variety is later removed from the vault. Size is the plant diameter;
/// spacing is empty space between neighbouring footprints, in either axis.
class ZoneSeed {
  const ZoneSeed({
    required this.varietyId,
    required this.name,
    required this.size,
    required this.spacing,
    this.plantOn,
  });

  /// The Seed Vault variety's ID.
  final String varietyId;

  /// What the gardener sees, e.g. "Big Beef · Tomatoes".
  final String name;

  /// Plant footprint diameter, in metres.
  final double size;

  /// Empty edge-to-edge gap between plants and plant lines, in metres.
  final double spacing;

  /// The day it goes in the ground (midnight UTC), from which its growing
  /// and harvest dates are counted; null until chosen.
  final DateTime? plantOn;

  /// Centre-to-centre distance along and across planting lines.
  double get pitch => size + spacing;

  /// Why these values cannot be used, or null when they can.
  String? get problem {
    if (!(size > 0) || !size.isFinite) {
      return 'Plant size must be above 0';
    }
    if (!(spacing >= 0) || !spacing.isFinite) {
      return 'Plant spacing must be a finite distance of 0 or more';
    }
    if (!pitch.isFinite) return 'Plant size plus spacing must be finite';
    return null;
  }

  ZoneSeed copyWith({
    double? size,
    double? spacing,
    DateTime? Function()? plantOn,
  }) => ZoneSeed(
    varietyId: varietyId,
    name: name,
    size: size ?? this.size,
    spacing: spacing ?? this.spacing,
    plantOn: plantOn == null ? this.plantOn : plantOn(),
  );

  @override
  bool operator ==(Object other) =>
      other is ZoneSeed &&
      other.varietyId == varietyId &&
      other.name == name &&
      other.size == size &&
      other.spacing == spacing &&
      other.plantOn == plantOn;

  @override
  int get hashCode => Object.hash(varietyId, name, size, spacing, plantOn);
}
