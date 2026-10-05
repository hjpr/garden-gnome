import 'ground.dart';

export 'ground.dart';

/// The kinds of land a layer can describe.
///
/// A property is land you hold: properties may not overlap one another.
/// A zone marks how part of it is used, such as beds or an orchard. A zone
/// must stay within the property it is listed under, but zones may overlap
/// and touch each other there.
enum LayerKind {
  property('Property'),
  zone('Zone');

  const LayerKind(this.label);

  final String label;

  /// The kind of layer this one is listed under in Layers and must stay
  /// within, if any.
  LayerKind? get parentKind => switch (this) {
    LayerKind.property => null,
    LayerKind.zone => LayerKind.property,
  };

  /// Whether land of this kind must stand alone: none of its shapes may
  /// overlap each other or another layer of the same kind.
  bool get exclusive => this == LayerKind.property;
}

/// What a layer is for, as the gardener sees it. Beds and plantings are
/// both zones underneath (they share drawing rules), but they are added,
/// listed and edited as separate kinds so their purpose is never hidden.
enum LayerRole {
  /// Land you hold.
  property('Property'),

  /// Ground inside a property: Fallow, Flat, or Row.
  bed('Bed'),

  /// What grows where: drawn over beds and planted from the Seed Vault.
  planting('Planting');

  const LayerRole(this.label);

  final String label;

  LayerKind get kind =>
      this == LayerRole.property ? LayerKind.property : LayerKind.zone;

  /// The settings a new layer of this role starts with. A new bed is
  /// Flat, so a planting drawn over it grows straight away.
  LayerProperties get defaults => switch (this) {
    LayerRole.property => const PropertyProperties(),
    LayerRole.bed => const ZoneProperties(ground: GroundType.flat),
    LayerRole.planting => const ZoneProperties(ground: GroundType.grow),
  };
}

/// Outline colours offered for properties and zones, in menu order.
enum OutlineColor {
  green('Green', 0xFF465B3C),
  blue('Blue', 0xFF376B95),
  brown('Brown', 0xFF82603E),
  purple('Purple', 0xFF805891),
  orange('Orange', 0xFFB26930),
  sage('Green', 0xFF99A18F),
  olive('Olive', 0xFF6B7F4F);

  const OutlineColor(this.label, this.argb);

  final String label;
  final int argb;

  String get hex => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static OutlineColor? fromHex(String value) {
    for (final color in values) {
      if (color.hex == value.toLowerCase()) return color;
    }
    return null;
  }

  static const propertyChoices = [green, blue, brown, purple, orange];
  static const zoneChoices = [sage, olive, blue, brown, purple, orange];
}

/// Settings a user edits in a layer's Properties panel.
sealed class LayerProperties {
  const LayerProperties();

  static LayerProperties defaultsFor(LayerKind kind) => switch (kind) {
    LayerKind.property => const PropertyProperties(),
    LayerKind.zone => const ZoneProperties(),
  };
}

/// Settings for a property layer.
class PropertyProperties extends LayerProperties {
  const PropertyProperties({this.color = OutlineColor.green});

  final OutlineColor color;

  PropertyProperties copyWith({OutlineColor? color}) =>
      PropertyProperties(color: color ?? this.color);
}

/// Settings for a zone layer.
class ZoneProperties extends LayerProperties {
  const ZoneProperties({
    this.color = OutlineColor.sage,
    this.ground,
    this.rows = const RowSpec(),
    this.crop,
    this.seed,
    this.cover,
  });

  final OutlineColor color;

  /// How the soil is prepared, set with the Ground tool; null for plain
  /// dirt. [GroundType.grow] marks a grow zone.
  final GroundType? ground;

  /// Row size and heading. Used while [ground] is [GroundType.row], and
  /// kept when it is not, so switching back restores them. Flat ground
  /// uses only the direction, to line up the plants grow zones put on it.
  final RowSpec rows;

  /// The crop growing here, as a label.
  final String? crop;

  /// The seed planted here. Only grow zones are planted; the seed is kept
  /// when the ground changes, so switching back to Grow restores it.
  final ZoneSeed? seed;

  /// The cover crop sown here. Used while [ground] is [GroundType.cover],
  /// and kept when it is not, so switching back restores it.
  final CoverSowing? cover;

  /// Whether this zone is a grow zone, which Plant mode works on.
  bool get isGrow => ground == GroundType.grow;

  /// Whether this is a Cover bed, which Plant mode sows cover crops on.
  bool get isCover => ground == GroundType.cover;

  ZoneProperties copyWith({
    OutlineColor? color,
    GroundType? Function()? ground,
    RowSpec? rows,
    String? Function()? crop,
    ZoneSeed? Function()? seed,
    CoverSowing? Function()? cover,
  }) => ZoneProperties(
    color: color ?? this.color,
    ground: ground == null ? this.ground : ground(),
    rows: rows ?? this.rows,
    crop: crop == null ? this.crop : crop(),
    seed: seed == null ? this.seed : seed(),
    cover: cover == null ? this.cover : cover(),
  );
}

/// One property or zone in the drawing.
class Layer {
  Layer({
    required this.id,
    required this.kind,
    required this.name,
    required this.geometryId,
    required this.properties,
    this.parentId,
    List<String> children = const [],
    this.locked = false,
  }) : children = List.unmodifiable(children);

  final String id;
  final LayerKind kind;
  final String name;

  LayerRole get role => switch (properties) {
    PropertyProperties() => LayerRole.property,
    ZoneProperties(:final isGrow) =>
      isGrow ? LayerRole.planting : LayerRole.bed,
  };

  /// The property this layer is listed under; null for properties.
  final String? parentId;

  /// Layers listed under this property, in creation order.
  final List<String> children;
  final String geometryId;
  final LayerProperties properties;

  /// Set by the user once a layer is finished, so it is not changed by
  /// accident. See [GardenDocument.lockedBy].
  final bool locked;

  Layer copyWith({
    String? name,
    List<String>? children,
    LayerProperties? properties,
    bool? locked,
  }) => Layer(
    id: id,
    kind: kind,
    name: name ?? this.name,
    parentId: parentId,
    children: children ?? this.children,
    geometryId: geometryId,
    properties: properties ?? this.properties,
    locked: locked ?? this.locked,
  );
}

/// Checks a proposed layer name. Returns the cleaned name, or throws with a
/// reason the user can act on.
String validLayerName(String input) {
  final name = input.trim();
  if (name.isEmpty) throw const FormatException('Enter a name');
  if (name.contains('\n') || name.contains('\r')) {
    throw const FormatException('Use a single line');
  }
  if (name.runes.length > 120) {
    throw const FormatException('Use 120 characters or fewer');
  }
  return name;
}
