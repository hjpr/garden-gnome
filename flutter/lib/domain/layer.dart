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

enum SoilDrainage {
  excessive('Excessive'),
  good('Good'),
  moderate('Moderate'),
  fair('Fair'),
  poor('Poor');

  const SoilDrainage(this.label);

  final String label;
}

/// Decorative patterns drawn inside a closed boundary. They are for
/// looks only and never change area or land rules.
enum FillPattern {
  diagonal('Diagonal'),
  rows('Rows'),
  crosshatch('Crosshatch'),
  grid('Grid'),
  dots('Dots'),
  crosses('Crosses');

  const FillPattern(this.label);

  final String label;

  /// The pattern saved under [name], or null for none or an unknown name.
  static FillPattern? fromName(String? name) =>
      name == null ? null : values.asNameMap()[name];
}

enum PlantingType {
  flat('Flat'),
  row('Row'),
  mound('Mound');

  const PlantingType(this.label);

  final String label;
}

/// Soil sample values recorded for a property. Every value is optional.
class SoilSample {
  const SoilSample({
    this.ph,
    this.phosphorus,
    this.potassium,
    this.calcium,
    this.magnesium,
    this.cationExchange,
    this.conductivity,
    this.organicMatter,
  });

  final double? ph;
  final double? phosphorus;
  final double? potassium;
  final double? calcium;
  final double? magnesium;
  final double? cationExchange;
  final double? conductivity;
  final double? organicMatter;

  /// One entry per value, in display order, for listing and editing.
  static const fields = <(String, String)>[
    ('ph', 'pH'),
    ('phosphorus', 'Phosphorus'),
    ('potassium', 'Potassium'),
    ('calcium', 'Calcium'),
    ('magnesium', 'Magnesium'),
    // Short labels fit the Properties column.
    ('cationExchange', 'CEC'),
    ('conductivity', 'Conductivity'),
    ('organicMatter', 'Org. matter'),
  ];

  double? valueOf(String field) => switch (field) {
    'ph' => ph,
    'phosphorus' => phosphorus,
    'potassium' => potassium,
    'calcium' => calcium,
    'magnesium' => magnesium,
    'cationExchange' => cationExchange,
    'conductivity' => conductivity,
    'organicMatter' => organicMatter,
    _ => throw ArgumentError.value(field, 'field'),
  };

  /// A copy with one value replaced (null clears it).
  SoilSample withValue(String field, double? value) {
    double? pick(String name) => name == field ? value : valueOf(name);
    valueOf(field); // Rejects unknown names.
    return SoilSample(
      ph: pick('ph'),
      phosphorus: pick('phosphorus'),
      potassium: pick('potassium'),
      calcium: pick('calcium'),
      magnesium: pick('magnesium'),
      cationExchange: pick('cationExchange'),
      conductivity: pick('conductivity'),
      organicMatter: pick('organicMatter'),
    );
  }
}

/// Settings a user edits in a layer's Properties panel.
sealed class LayerProperties {
  const LayerProperties();

  /// The decorative pattern drawn over all of the layer's land.
  FillPattern? get pattern;

  /// A copy with the pattern replaced (null for none).
  LayerProperties withPattern(FillPattern? pattern);

  static LayerProperties defaultsFor(LayerKind kind) => switch (kind) {
    LayerKind.property => const PropertyProperties(),
    LayerKind.zone => const ZoneProperties(),
  };
}

/// Settings for a property layer.
class PropertyProperties extends LayerProperties {
  const PropertyProperties({
    this.color = OutlineColor.green,
    this.drainage,
    this.soil = const SoilSample(),
    this.pattern,
  });

  final OutlineColor color;
  final SoilDrainage? drainage;
  final SoilSample soil;
  @override
  final FillPattern? pattern;

  PropertyProperties copyWith({
    OutlineColor? color,
    SoilDrainage? Function()? drainage,
    SoilSample? soil,
    FillPattern? Function()? pattern,
  }) => PropertyProperties(
    color: color ?? this.color,
    drainage: drainage == null ? this.drainage : drainage(),
    soil: soil ?? this.soil,
    pattern: pattern == null ? this.pattern : pattern(),
  );

  @override
  PropertyProperties withPattern(FillPattern? pattern) =>
      copyWith(pattern: () => pattern);
}

/// Settings for a zone layer.
class ZoneProperties extends LayerProperties {
  const ZoneProperties({
    this.color = OutlineColor.sage,
    this.pattern,
    this.ground,
    this.crop,
    this.plantingType = PlantingType.flat,
  });

  final OutlineColor color;
  @override
  final FillPattern? pattern;

  /// A short description of the ground, such as "raised beds".
  final String? ground;

  /// The crop growing here, as a label.
  final String? crop;

  /// How the crop is planted. Kept for the planting layouts to come.
  final PlantingType plantingType;

  ZoneProperties copyWith({
    OutlineColor? color,
    String? Function()? ground,
    String? Function()? crop,
    FillPattern? Function()? pattern,
  }) => ZoneProperties(
    color: color ?? this.color,
    pattern: pattern == null ? this.pattern : pattern(),
    ground: ground == null ? this.ground : ground(),
    crop: crop == null ? this.crop : crop(),
    plantingType: plantingType,
  );

  @override
  ZoneProperties withPattern(FillPattern? pattern) =>
      copyWith(pattern: () => pattern);
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
