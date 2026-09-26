/// The kinds of land a layer can describe, from largest to smallest.
enum LayerKind {
  field('Field'),
  plot('Plot'),
  area('Area');

  const LayerKind(this.label);

  final String label;

  /// The kind a layer of this kind must sit inside, if any.
  LayerKind? get parentKind => switch (this) {
    LayerKind.field => null,
    LayerKind.plot => LayerKind.field,
    LayerKind.area => LayerKind.plot,
  };

  /// The kind of layer this one is listed under in Layers: plots and
  /// areas both belong to a field, so an area can reach into any plot.
  LayerKind? get homeKind => this == LayerKind.field ? null : LayerKind.field;

  LayerKind? get childKind => switch (this) {
    LayerKind.field => LayerKind.plot,
    LayerKind.plot => LayerKind.area,
    LayerKind.area => null,
  };
}

/// Outline colours offered for fields and plots, in menu order.
enum OutlineColor {
  green('Green', 0xFF465B3C),
  blue('Blue', 0xFF376B95),
  brown('Brown', 0xFF82603E),
  purple('Purple', 0xFF805891),
  orange('Orange', 0xFFB26930),
  sage('Green', 0xFF99A18F);

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

  static const fieldChoices = [green, blue, brown, purple, orange];
  static const plotChoices = [sage, blue, brown, purple, orange];
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

/// Soil sample values recorded for a field. Every value is optional.
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
    LayerKind.field => const FieldProperties(),
    LayerKind.plot => const PlotProperties(),
    LayerKind.area => const AreaProperties(),
  };
}

class FieldProperties extends LayerProperties {
  const FieldProperties({
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

  FieldProperties copyWith({
    OutlineColor? color,
    SoilDrainage? Function()? drainage,
    SoilSample? soil,
    FillPattern? Function()? pattern,
  }) => FieldProperties(
    color: color ?? this.color,
    drainage: drainage == null ? this.drainage : drainage(),
    soil: soil ?? this.soil,
    pattern: pattern == null ? this.pattern : pattern(),
  );

  @override
  FieldProperties withPattern(FillPattern? pattern) =>
      copyWith(pattern: () => pattern);
}

class PlotProperties extends LayerProperties {
  const PlotProperties({
    this.color = OutlineColor.sage,
    this.pattern,
    this.ground,
  });

  final OutlineColor color;
  @override
  final FillPattern? pattern;

  /// A short description of the ground, such as "raised beds".
  final String? ground;

  PlotProperties copyWith({
    OutlineColor? color,
    String? Function()? ground,
    FillPattern? Function()? pattern,
  }) => PlotProperties(
    color: color ?? this.color,
    pattern: pattern == null ? this.pattern : pattern(),
    ground: ground == null ? this.ground : ground(),
  );

  @override
  PlotProperties withPattern(FillPattern? pattern) =>
      copyWith(pattern: () => pattern);
}

class AreaProperties extends LayerProperties {
  const AreaProperties({
    this.plantingType = PlantingType.flat,
    this.crop,
    this.pattern,
  });

  final PlantingType plantingType;

  /// The crop growing here, as a label.
  final String? crop;
  @override
  final FillPattern? pattern;

  AreaProperties copyWith({
    String? Function()? crop,
    FillPattern? Function()? pattern,
  }) => AreaProperties(
    plantingType: plantingType,
    crop: crop == null ? this.crop : crop(),
    pattern: pattern == null ? this.pattern : pattern(),
  );

  @override
  AreaProperties withPattern(FillPattern? pattern) =>
      copyWith(pattern: () => pattern);
}

/// One field, plot, or area in the drawing.
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

  /// The field this layer is listed under; null for fields. Where its
  /// land may sit is set by [LayerKind.parentKind], not by this.
  final String? parentId;

  /// Layers listed under this field, in creation order.
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
