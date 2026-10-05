import 'dart:math' as math;

/// How a bed's soil is prepared. A bed with no ground set is fallow:
/// unprepared dirt that nothing is planted on. [grow] marks a planting
/// rather than soil.
enum GroundType {
  /// Sown with a cover crop across the whole bed. Plantings over it are
  /// not planted: the bed is taken until it goes back to Flat or Row.
  cover('Cover'),

  /// One level, prepared bed across the whole zone.
  flat('Flat'),

  /// Parallel planting rows with paths between them; see [RowSpec].
  row('Row'),

  /// A grow zone: not soil of its own, but an area drawn over Flat or Row
  /// ground to say what is planted there. Seeds are dropped on it in
  /// Plan's Plant mode, and plants follow the ground underneath.
  grow('Grow');

  const GroundType(this.label);

  final String label;

  /// Whether this is soil that plantings plant on (Flat, Row). Cover beds,
  /// like fallow ones, are not planted.
  bool get isSoil => this == flat || this == row;

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

/// The cover crop sown across a Cover bed: which Seed Vault variety, and
/// when it went in and was (or will be) terminated. Days are UTC dates.
class CoverSowing {
  const CoverSowing({
    required this.varietyId,
    required this.name,
    this.sownOn,
    this.terminatedOn,
  });

  /// The Seed Vault variety's ID.
  final String varietyId;

  /// Kept with the drawing so it still reads if the variety is removed.
  final String name;
  final DateTime? sownOn;

  /// Mowed, tilled or tarped under; never before [sownOn].
  final DateTime? terminatedOn;

  /// Whether it is in the ground on [today]: sown (or planned) and not
  /// yet terminated.
  bool isGrowingOn(DateTime today) =>
      sownOn != null && (terminatedOn == null || terminatedOn!.isAfter(today));

  CoverSowing copyWith({
    DateTime? Function()? sownOn,
    DateTime? Function()? terminatedOn,
  }) => CoverSowing(
    varietyId: varietyId,
    name: name,
    sownOn: sownOn == null ? this.sownOn : sownOn(),
    terminatedOn: terminatedOn == null ? this.terminatedOn : terminatedOn(),
  );

  @override
  bool operator ==(Object other) =>
      other is CoverSowing &&
      other.varietyId == varietyId &&
      other.name == name &&
      other.sownOn == sownOn &&
      other.terminatedOn == terminatedOn;

  @override
  int get hashCode => Object.hash(varietyId, name, sownOn, terminatedOn);
}

/// The seed planted in a grow zone: which Seed Vault variety, and how far
/// apart its plants go.
///
/// The name is kept with the drawing so it still reads correctly if the
/// variety is later removed from the vault. Both spacings are centre to
/// centre, as seed catalogs give them: [inRow] between plants along a
/// line, [betweenRows] between neighbouring lines.
class ZoneSeed {
  const ZoneSeed({
    required this.varietyId,
    required this.name,
    required this.inRow,
    required this.betweenRows,
    this.lines,
  });

  /// The Seed Vault variety's ID.
  final String varietyId;

  /// What the gardener sees, e.g. "Big Beef · Tomatoes".
  final String name;

  /// Centre-to-centre distance between plants along a line, in metres.
  final double inRow;

  /// Centre-to-centre distance between lines of plants, in metres.
  final double betweenRows;

  /// Most lines of plants along each row bed; null fills the row with as
  /// many lines as fit. Flat ground is a grid and ignores it.
  final int? lines;

  /// The room one plant takes: the closer of its two spacings. Plants
  /// keep half of it clear of line ends and bed edges.
  double get footprint => inRow < betweenRows ? inRow : betweenRows;

  /// Why these values cannot be used, or null when they can.
  String? get problem {
    if (!(inRow > 0) || !inRow.isFinite) {
      return 'In-row spacing must be above 0';
    }
    if (!(betweenRows > 0) || !betweenRows.isFinite) {
      return 'Between-row spacing must be above 0';
    }
    if (lines case final n? when n < 1) return 'Lines must be 1 or more';
    return null;
  }

  ZoneSeed copyWith({
    double? inRow,
    double? betweenRows,
    int? Function()? lines,
  }) => ZoneSeed(
    varietyId: varietyId,
    name: name,
    inRow: inRow ?? this.inRow,
    betweenRows: betweenRows ?? this.betweenRows,
    lines: lines == null ? this.lines : lines(),
  );

  @override
  bool operator ==(Object other) =>
      other is ZoneSeed &&
      other.varietyId == varietyId &&
      other.name == name &&
      other.inRow == inRow &&
      other.betweenRows == betweenRows &&
      other.lines == lines;

  @override
  int get hashCode => Object.hash(varietyId, name, inRow, betweenRows, lines);
}
