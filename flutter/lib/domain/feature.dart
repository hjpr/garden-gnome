import 'dart:math' as math;

import 'vec.dart';

/// Things built on the land, placed with the Feature tool.
///
/// Default sizes are common kit sizes, in metres: an 8 × 4 ft bed a foot
/// tall, a 12 × 8 ft hobby greenhouse and a 30 × 14 ft high tunnel.
enum FeatureKind {
  raisedBed('Raised bed', 2.4384, 1.2192, 0.3048),
  greenhouse('Greenhouse', 3.6576, 2.4384, 2.4384),
  highTunnel('High tunnel', 9.144, 4.2672, 3.048);

  const FeatureKind(
    this.label,
    this.defaultLength,
    this.defaultWidth,
    this.defaultHeight,
  );

  final String label;
  final double defaultLength;
  final double defaultWidth;
  final double defaultHeight;
}

/// High tunnels are drawn from 5 ft sections: an end section at each end
/// and middle sections between, so any length looks right without
/// stretching the picture.
const double tunnelSectionLength = 1.524;

/// How many 5 ft sections draw a high tunnel [length] metres long: the
/// length rounded to the nearest 5 ft, and never fewer than the two ends.
/// A 79 ft tunnel is drawn as 16 sections, 80 ft.
int tunnelSections(double length) =>
    math.max(2, (length / tunnelSectionLength).round());

/// One raised bed, greenhouse or high tunnel: a rectangle on the ground
/// with a height. Features sit on top of the land and do not change area
/// or land rules.
class Feature {
  const Feature({
    required this.id,
    required this.kind,
    required this.centre,
    required this.length,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.label,
  });

  /// A new feature of [kind] at its default size, centred on [centre].
  factory Feature.placed(String id, FeatureKind kind, Vec centre) => Feature(
    id: id,
    kind: kind,
    centre: centre,
    length: kind.defaultLength,
    width: kind.defaultWidth,
    height: kind.defaultHeight,
  );

  /// "feature-N", numbered by the document's feature counter.
  final String id;
  final FeatureKind kind;
  final Vec centre;

  /// Along the feature's long side, in metres. At rotation 0 it runs
  /// left to right on the screen.
  final double length;

  /// Across the feature, in metres.
  final double width;

  /// Top above the ground, in metres. Kept for the 3D view to come.
  final double height;

  /// Degrees clockwise.
  final double rotation;

  /// A name the user gave it, or null for the automatic one.
  final String? label;

  /// The name shown in Layers and Properties: the label, or the kind and
  /// the number from its ID ("Raised bed 3").
  String get displayName =>
      label ?? '${kind.label} ${id.substring(id.lastIndexOf('-') + 1)}';

  double get footprint => length * width;

  /// Why these sizes cannot be used, or null when they can.
  String? get problem {
    for (final (name, value) in [
      ('Length', length),
      ('Width', width),
      ('Height', height),
    ]) {
      if (!(value > 0) || !value.isFinite) return '$name must be above 0';
    }
    if (!rotation.isFinite || !centre.isFinite) return 'Enter a number';
    return null;
  }

  (Vec, Vec) get _axes {
    final radians = rotation * math.pi / 180;
    final along = Vec(math.cos(radians), math.sin(radians));
    return (along, Vec(-along.y, along.x));
  }

  /// Corners clockwise from the one that is top-left at rotation 0.
  List<Vec> get corners {
    final (along, across) = _axes;
    final a = along * (length / 2);
    final b = across * (width / 2);
    return [centre - a - b, centre + a - b, centre + a + b, centre - a + b];
  }

  /// Whether [p] lies on or inside the footprint.
  bool contains(Vec p) {
    final (along, across) = _axes;
    final d = p - centre;
    return d.dot(along).abs() <= length / 2 + 1e-9 &&
        d.dot(across).abs() <= width / 2 + 1e-9;
  }

  Feature copyWith({
    Vec? centre,
    double? length,
    double? width,
    double? height,
    double? rotation,
    String? Function()? label,
  }) => Feature(
    id: id,
    kind: kind,
    centre: centre ?? this.centre,
    length: length ?? this.length,
    width: width ?? this.width,
    height: height ?? this.height,
    rotation: rotation == null ? this.rotation : _normalAngle(rotation),
    label: label == null ? this.label : label(),
  );

  static double _normalAngle(double degrees) {
    final folded = degrees % 360;
    return folded < 0 ? folded + 360 : folded;
  }

  @override
  bool operator ==(Object other) =>
      other is Feature &&
      other.id == id &&
      other.kind == kind &&
      other.centre == centre &&
      other.length == length &&
      other.width == width &&
      other.height == height &&
      other.rotation == rotation &&
      other.label == label;

  @override
  int get hashCode =>
      Object.hash(id, kind, centre, length, width, height, rotation, label);
}
