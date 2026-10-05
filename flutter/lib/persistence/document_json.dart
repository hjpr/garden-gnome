import 'dart:typed_data';

import '../application/storage_error.dart';
import '../domain/document.dart';
import '../domain/feature.dart';
import '../domain/geometry.dart';
import '../domain/grow/climate.dart';
import '../domain/grow/planting.dart';
import '../domain/layer.dart';
import '../domain/reference_image.dart';
import '../domain/vec.dart';
import 'garden_record_codec.dart'
    show climateFromJson, climateToJson, plantingFromJson, plantingToJson;

// Raise it whenever an older reader would lose or misread something, so it
// refuses the file instead of re-saving it lossy.
//
// 2: zone ground (flat/row) and row sizes, features; patterns removed.
// 3: grow zones (ground "grow") and the seed planted in them.
// 4: explicit plant diameter and empty gap, replacing centre distances.
// 5: property soil drainage and soil sample removed (older readers
//    require them).
// 6: an empty Reference layer is kept (older readers would drop it).
// 7: a planting's plant-on date (older readers would drop it).
// 8: the farm's climate and plantings (older readers would drop them).
// 9: plantings name their planting layer; a planting layer's Plant on
//    date moves into a sown planting (older readers would drop the link).
// 10: greenhouse flats and pots on plantings (older readers would drop
//     them).
// 11: a planting seed's lines per row (older readers would fill rows).
// 12: Cover beds (ground "cover") and their cover crop sowing (older
//     readers would refuse the ground name).
// 13: a planting seed's in-row and between-row centre distances replace
//     size and gap (older readers require them).
const int schemaVersion = 13;

/// The oldest version still opened. Version 1 files open with their
/// patterns and free-text ground notes dropped.
const int oldestSchemaVersion = 1;
const String formatName = 'garden-gnome';

/// Where a reference picture is kept inside the ZIP, by ID and type.
String referenceAssetEntry(String id, String mimeType) =>
    'assets/$id.${mimeType.split('/').last}';

// ---------------------------------------------------------------- writing

Map<String, Object?> documentToJson(GardenDocument d) => {
  'format': formatName,
  'schema_version': schemaVersion,
  'document_id': d.id,
  'property_ids': d.propertyIds,
  'name_counters': {
    for (final entry in d.nameCounters.entries) entry.key.name: entry.value,
  },
  'layers': {
    for (final layer in d.layers.values) layer.id: _layerToJson(layer),
  },
  'geometries': {for (final g in d.geometries.values) g.id: _geometryToJson(g)},
  'image_counter': d.imageCounter,
  'reference_layer': d.hasReferenceLayer,
  'references': [for (final image in d.references) _referenceToJson(image)],
  'feature_counter': d.featureCounter,
  'features': [for (final f in d.features) _featureToJson(f)],
  'climate': climateToJson(d.climate),
  'planting_counter': d.plantingCounter,
  'plantings': [for (final p in d.plantings.values) plantingToJson(p)],
};

Map<String, Object?> _featureToJson(Feature f) => {
  'id': f.id,
  'kind': f.kind.name,
  'centre': _vecToJson(f.centre),
  'length': f.length,
  'width': f.width,
  'height': f.height,
  'rotation': f.rotation,
  'label': f.label,
};

Map<String, Object?> _referenceToJson(ReferenceImage image) => {
  'id': image.id,
  'label': image.label,
  'file_name': image.fileName,
  'asset': referenceAssetEntry(image.id, image.mimeType),
  'mime_type': image.mimeType,
  'pixel_width': image.pixelWidth,
  'pixel_height': image.pixelHeight,
  'top_left': _vecToJson(image.topLeft),
  'metres_per_pixel': image.metresPerPixel,
  'line_start': image.lineStart == null ? null : _vecToJson(image.lineStart!),
  'line_end': image.lineEnd == null ? null : _vecToJson(image.lineEnd!),
  'known_distance': image.knownDistance,
  'opacity': image.opacity,
  'locked': image.locked,
};

Map<String, Object?> _vecToJson(Vec v) => {'x': v.x, 'y': v.y};

Map<String, Object?> _layerToJson(Layer layer) => {
  'kind': layer.kind.name,
  'name': layer.name,
  'parent_id': layer.parentId,
  'children': layer.children,
  'geometry_id': layer.geometryId,
  'locked': layer.locked,
  'properties': switch (layer.properties) {
    PropertyProperties p => {'color': p.color.name},
    ZoneProperties p => {
      'color': p.color.name,
      'ground': p.ground?.name,
      'rows': {
        'width': p.rows.width,
        'spacing': p.rows.spacing,
        'direction': p.rows.direction,
        'border': p.rows.border,
      },
      'crop': p.crop,
      if (p.seed case final seed?)
        'seed': {
          'variety_id': seed.varietyId,
          'name': seed.name,
          'in_row': seed.inRow,
          'between_rows': seed.betweenRows,
          'lines': ?seed.lines,
        },
      if (p.cover case final cover?)
        'cover': {
          'variety_id': cover.varietyId,
          'name': cover.name,
          if (cover.sownOn case final d?) 'sown_on': _dayToJson(d),
          if (cover.terminatedOn case final d?) 'terminated_on': _dayToJson(d),
        },
    },
  },
};

Map<String, Object?> _geometryToJson(Geometry g) => {
  'owner_layer_id': g.ownerLayerId,
  'points': {
    for (final e in g.points.entries) e.key: {'x': e.value.x, 'y': e.value.y},
  },
  'lines': {
    for (final l in g.lines.values)
      l.id: {
        'start': l.start,
        'end': l.end,
        'bulge': l.bulge,
        if (l.startHandle case final h?) 'start_handle': {'x': h.x, 'y': h.y},
        if (l.endHandle case final h?) 'end_handle': {'x': h.x, 'y': h.y},
      },
  },
  'circles': {
    for (final c in g.circles.values)
      c.id: {'center': c.center, 'radius': c.radius, 'label': c.label},
  },
  'shapes': {
    for (final s in g.shapes.values)
      s.id: {
        'segments': [
          for (final ref in s.segments)
            {'segment_id': ref.segmentId, 'reversed': ref.reversed},
        ],
        'holes': [
          for (final ring in s.holes)
            [
              for (final ref in ring)
                {'segment_id': ref.segmentId, 'reversed': ref.reversed},
            ],
        ],
        'label': s.label,
      },
  },
  'order': g.stack,
  'last_ids': {
    'points': g.counters.points,
    'lines': g.counters.lines,
    'circles': g.counters.circles,
    'shapes': g.counters.shapes,
  },
  if (g.dimensions case final dims?)
    'dimensions': {
      'row_width': dims.rowWidth,
      'row_spacing': dims.rowSpacing,
      'row_direction': dims.rowDirection,
      'mound_diameter': dims.moundDiameter,
      'mound_spacing': dims.moundSpacing,
    },
};

// ---------------------------------------------------------------- reading

/// Builds a document from decoded JSON, rejecting anything damaged.
///
/// Nothing is repaired or dropped: a file either opens exactly as saved or
/// is refused with a reason. Land that breaks a drawing rule (for example
/// two overlapping properties) is not damage; it opens and is shown
/// invalid, just as it was when saved.
///
/// [readAsset] returns the bytes of a file stored beside the drawing in
/// the ZIP, or null when it is missing.
GardenDocument documentFromJson(
  Object? json, {
  List<int>? Function(String name)? readAsset,
}) {
  final root = _map(json, 'document');
  if (root['format'] != formatName) {
    throw const DocumentFormatError('This is not a Garden Gnome file');
  }
  final version = root['schema_version'];
  if (version is int && version > schemaVersion) {
    throw const DocumentFormatError(
      'This file was made by a newer version of Garden Gnome',
    );
  }
  if (version is! int || version < oldestSchemaVersion) {
    throw const DocumentFormatError('Damaged file: unsupported schema version');
  }

  final geometries = <String, Geometry>{};
  _map(root['geometries'], 'geometries').forEach((id, value) {
    geometries[id] = _geometryFromJson(id, _map(value, 'geometry'));
  });
  final layers = <String, Layer>{};
  _map(root['layers'], 'layers').forEach((id, value) {
    final json = _map(value, 'layer');
    layers[id] = version == 1
        ? _layerFromJsonV1(id, json, geometries[json['geometry_id']])
        : _layerFromJson(id, json, version);
  });

  final references = [
    for (final item in _list(root['references'], 'references'))
      _referenceFromJson(_map(item, 'reference'), readAsset),
  ];
  final imageCounter = _count(root['image_counter']);
  final imageIds = <String>{};
  for (final image in references) {
    if (!imageIds.add(image.id)) {
      throw const DocumentFormatError('Damaged file: an image appears twice');
    }
    final number = int.tryParse(
      image.id.substring(image.id.lastIndexOf('-') + 1),
    );
    if (!image.id.startsWith('image-') ||
        number == null ||
        number > imageCounter) {
      throw const DocumentFormatError('Damaged file: an image ID is not valid');
    }
  }

  final featureCounter = version == 1 ? 0 : _count(root['feature_counter']);
  final features = version == 1
      ? const <Feature>[]
      : [
          for (final item in _list(root['features'], 'features'))
            _featureFromJson(_map(item, 'feature')),
        ];
  final featureIds = <String>{};
  for (final feature in features) {
    final number = int.tryParse(
      feature.id.substring(feature.id.lastIndexOf('-') + 1),
    );
    if (!featureIds.add(feature.id) ||
        !feature.id.startsWith('feature-') ||
        number == null ||
        number > featureCounter) {
      throw const DocumentFormatError(
        'Damaged file: a feature ID is not valid',
      );
    }
  }

  final (climate, plantings, plantingCounter) = _farmFromJson(root, version);

  final nameCounters = <LayerKind, int>{};
  _map(root['name_counters'], 'name counters').forEach((k, v) {
    nameCounters[_enum(LayerKind.values, k, 'layer kind')] = _count(v);
  });

  final document = GardenDocument(
    id: _string(root['document_id'], 'document ID'),
    layers: layers,
    geometries: geometries,
    propertyIds: _strings(root['property_ids'], 'properties'),
    nameCounters: nameCounters,
    references: references,
    referenceLayer:
        version >= 6 && _bool(root['reference_layer'], 'Reference layer'),
    imageCounter: imageCounter,
    features: features,
    featureCounter: featureCounter,
    climate: climate,
    plantings: plantings,
    plantingCounter: plantingCounter,
  );
  _checkStructure(document);
  return document;
}

Layer _layerFromJson(String id, Map<String, Object?> json, int version) {
  final kind = _enum(LayerKind.values, json['kind'], 'layer kind');
  final props = _map(json['properties'], 'properties');
  return _layerShell(id, json, kind, switch (kind) {
    LayerKind.property => _propertyFromJson(props),
    LayerKind.zone => ZoneProperties(
      color: _enum(OutlineColor.values, props['color'], 'color'),
      ground: props['ground'] == null
          ? null
          : _enum(GroundType.values, props['ground'], 'ground'),
      rows: _rowsFromJson(_map(props['rows'], 'rows')),
      crop: _optionalString(props['crop'], 'crop'),
      seed: props['seed'] == null
          ? null
          : _seedFromJson(_map(props['seed'], 'seed'), version),
      cover: props['cover'] == null
          ? null
          : _coverFromJson(_map(props['cover'], 'cover')),
    ),
  });
}

CoverSowing _coverFromJson(Map<String, Object?> json) {
  DateTime? day(String key) =>
      json[key] == null ? null : _dayFromJson(json[key]);
  final sown = day('sown_on'), terminated = day('terminated_on');
  if (sown != null && terminated != null && terminated.isBefore(sown)) {
    throw const DocumentFormatError('Damaged file: cover crop dates');
  }
  return CoverSowing(
    varietyId: _string(json['variety_id'], 'cover crop variety'),
    name: _string(json['name'], 'cover crop name'),
    sownOn: sown,
    terminatedOn: terminated,
  );
}

ZoneSeed _seedFromJson(Map<String, Object?> json, int version) {
  final double inRow, betweenRows;
  if (version >= 4 && version < 13) {
    // Size plus gap was one centre distance used both ways; keep it so
    // the planting lays out as it did.
    final size = _number(json['size']), gap = _number(json['spacing']);
    if (!(size > 0) || !(gap >= 0)) {
      throw const DocumentFormatError('Damaged file: seed spacing');
    }
    final pitch = size + gap;
    inRow = pitch;
    betweenRows = pitch;
  } else {
    inRow = _number(json['in_row']);
    betweenRows = _number(json['between_rows']);
  }
  final seed = ZoneSeed(
    varietyId: _string(json['variety_id'], 'seed variety'),
    name: _string(json['name'], 'seed name'),
    inRow: inRow,
    betweenRows: betweenRows,
    lines: json['lines'] == null ? null : _count(json['lines']),
  );
  if (seed.problem != null) {
    throw const DocumentFormatError('Damaged file: seed spacing');
  }
  return seed;
}

/// Version 1 layers: patterns and planting type are dropped, and the
/// free-text ground note too, unless it names a ground type. Row sizes
/// come from the zone's geometry, where version 1 kept them.
Layer _layerFromJsonV1(
  String id,
  Map<String, Object?> json,
  Geometry? geometry,
) {
  final kind = _enum(LayerKind.values, json['kind'], 'layer kind');
  final props = _map(json['properties'], 'properties');
  final note = _optionalString(props['ground'], 'ground')?.trim().toLowerCase();
  final dims = geometry?.dimensions;
  const defaults = RowSpec();
  return _layerShell(id, json, kind, switch (kind) {
    LayerKind.property => _propertyFromJson(props),
    LayerKind.zone => ZoneProperties(
      color: _enum(OutlineColor.values, props['color'], 'color'),
      ground: GroundType.values.where((g) => g.name == note).firstOrNull,
      rows: RowSpec(
        width: dims?.rowWidth ?? defaults.width,
        spacing: dims?.rowSpacing ?? defaults.spacing,
        direction: RowSpec.normalDirection(dims?.rowDirection ?? 0),
      ),
      crop: _optionalString(props['crop'], 'crop'),
    ),
  });
}

Layer _layerShell(
  String id,
  Map<String, Object?> json,
  LayerKind kind,
  LayerProperties properties,
) {
  final String name;
  try {
    name = validLayerName(_string(json['name'], 'layer name'));
  } on FormatException catch (e) {
    throw DocumentFormatError('A layer name is not valid: ${e.message}');
  }
  return Layer(
    id: id,
    kind: kind,
    name: name,
    parentId: _optionalString(json['parent_id'], 'parent ID'),
    children: _strings(json['children'], 'children'),
    geometryId: _string(json['geometry_id'], 'geometry ID'),
    locked: _bool(json['locked'], 'layer lock'),
    properties: properties,
  );
}

/// Files before version 5 also hold soil drainage and soil sample
/// values; those features were removed and the values are ignored.
PropertyProperties _propertyFromJson(Map<String, Object?> props) =>
    PropertyProperties(
      color: _enum(OutlineColor.values, props['color'], 'color'),
    );

/// The farm's climate and plantings; files before version 8 have none.
(Climate, Map<String, Planting>, int) _farmFromJson(
  Map<String, Object?> root,
  int version,
) {
  if (version < 7) return (const Climate(), const {}, 0);
  if (version == 7) {
    final (plantings, counter) = _plantOnDates(root);
    return (const Climate(), plantings, counter);
  }
  try {
    final climate = climateFromJson(_map(root['climate'], 'climate'));
    final counter = _count(root['planting_counter']);
    final plantings = <String, Planting>{};
    for (final raw in _list(root['plantings'], 'plantings')) {
      final p = plantingFromJson(raw);
      final number = int.tryParse(p.id.substring(p.id.lastIndexOf('-') + 1));
      if (!p.id.startsWith('planting-') ||
          number == null ||
          number > counter ||
          plantings.containsKey(p.id)) {
        throw const DocumentFormatError(
          'Damaged file: a planting ID is not valid',
        );
      }
      plantings[p.id] = p;
    }
    return (climate, plantings, counter);
  } on FormatException catch (e) {
    throw DocumentFormatError('Damaged file: ${e.message}');
  }
}

/// Version 7 kept one Plant on date on a planting layer's seed. Each
/// becomes a planting sown in place that day, linked to its layer.
(Map<String, Planting>, int) _plantOnDates(Map<String, Object?> root) {
  final plantings = <String, Planting>{};
  _map(root['layers'], 'layers').forEach((layerId, value) {
    final props = _map(_map(value, 'layer')['properties'], 'properties');
    final seed = props['seed'];
    if (seed is! Map || seed['plant_on'] == null) return;
    final id = 'planting-${plantings.length + 1}';
    plantings[id] = Planting(
      id: id,
      varietyId: _string(seed['variety_id'], 'seed variety'),
      sownOn: _dayFromJson(seed['plant_on']),
      startedIndoors: false,
      layerId: layerId,
    );
  });
  return (plantings, plantings.length);
}

String _dayToJson(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime _dayFromJson(Object? value) {
  final match = value is String
      ? RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value)
      : null;
  if (match == null) {
    throw const DocumentFormatError('Damaged file: a planting date');
  }
  final day = DateTime.utc(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
  );
  if (_dayToJson(day) != value) {
    throw const DocumentFormatError('Damaged file: a planting date');
  }
  return day;
}

RowSpec _rowsFromJson(Map<String, Object?> json) {
  final rows = RowSpec(
    width: _number(json['width']),
    spacing: _number(json['spacing']),
    direction: _number(json['direction']),
    border: json.containsKey('border') ? _number(json['border']) : 0,
  );
  if (rows.problem != null || rows.direction < 0 || rows.direction >= 180) {
    throw const DocumentFormatError('Damaged file: row sizes');
  }
  return rows;
}

Feature _featureFromJson(Map<String, Object?> json) {
  final feature = Feature(
    id: _string(json['id'], 'feature ID'),
    kind: _enum(FeatureKind.values, json['kind'], 'feature kind'),
    centre: _vec(json['centre']),
    length: _number(json['length']),
    width: _number(json['width']),
    height: _number(json['height']),
    rotation: _number(json['rotation']),
    label: _optionalString(json['label'], 'feature name'),
  );
  if (feature.problem != null ||
      feature.rotation < 0 ||
      feature.rotation >= 360) {
    throw const DocumentFormatError('Damaged file: feature sizes');
  }
  return feature;
}

/// A Bézier handle offset, or null when the line has none.
Vec? _optionalHandle(Object? value) {
  if (value == null) return null;
  final h = _map(value, 'curve handle');
  return Vec(_number(h['x']), _number(h['y']));
}

Geometry _geometryFromJson(String id, Map<String, Object?> json) {
  final points = <String, Vec>{};
  _map(json['points'], 'points').forEach((pointId, value) {
    final p = _map(value, 'point');
    points[pointId] = Vec(_number(p['x']), _number(p['y']));
  });
  final lines = <String, LineSegment>{};
  _map(json['lines'], 'lines').forEach((lineId, value) {
    final l = _map(value, 'line');
    lines[lineId] = LineSegment(
      lineId,
      _string(l['start'], 'line start'),
      _string(l['end'], 'line end'),
      bulge: _number(l['bulge']),
      startHandle: _optionalHandle(l['start_handle']),
      endHandle: _optionalHandle(l['end_handle']),
    );
  });
  final circles = <String, Circle>{};
  _map(json['circles'], 'circles').forEach((circleId, value) {
    final c = _map(value, 'circle');
    final radius = _number(c['radius']);
    if (radius <= 0) {
      throw const DocumentFormatError('Damaged file: a circle has no size');
    }
    circles[circleId] = Circle(
      circleId,
      _string(c['center'], 'circle center'),
      radius,
      label: _optionalString(c['label'], 'circle label'),
    );
  });
  final shapes = <String, ClosedShape>{};
  _map(json['shapes'], 'shapes').forEach((shapeId, value) {
    final s = _map(value, 'shape');
    shapes[shapeId] = ClosedShape(
      shapeId,
      _ringFromJson(s['segments']),
      holes: [
        for (final ring in _list(s['holes'], 'holes')) _ringFromJson(ring),
      ],
      label: _optionalString(s['label'], 'shape label'),
    );
  });
  // The stack lists every shape and circle exactly once, bottom first.
  final order = _strings(json['order'], 'shape order');
  for (final item in order) {
    if (!shapes.containsKey(item) && !circles.containsKey(item)) {
      throw const DocumentFormatError('Damaged file: a shape is missing');
    }
  }
  if (order.toSet().length != order.length) {
    throw const DocumentFormatError('Damaged file: a shape appears twice');
  }
  if (order.length != shapes.length + circles.length) {
    throw const DocumentFormatError('Damaged file: a shape is not stacked');
  }
  final last = _map(json['last_ids'], 'counters');
  final dims = json['dimensions'] == null
      ? null
      : _map(json['dimensions'], 'dimensions');
  return Geometry(
    id: id,
    ownerLayerId: _string(json['owner_layer_id'], 'owner'),
    points: points,
    lines: lines,
    circles: circles,
    shapes: shapes,
    order: order,
    counters: IdCounters(
      points: _count(last['points']),
      lines: _count(last['lines']),
      circles: _count(last['circles']),
      shapes: _count(last['shapes']),
    ),
    dimensions: dims == null
        ? null
        : PlantingDimensions(
            rowWidth: _optionalNumber(dims['row_width']),
            rowSpacing: _optionalNumber(dims['row_spacing']),
            rowDirection: _optionalNumber(dims['row_direction']),
            moundDiameter: _optionalNumber(dims['mound_diameter']),
            moundSpacing: _optionalNumber(dims['mound_spacing']),
          ),
  );
}

List<SegmentRef> _ringFromJson(Object? value) => [
  for (final entry in _list(value, 'segments'))
    SegmentRef(
      _string(_map(entry, 'segment')['segment_id'], 'segment ID'),
      reversed: _bool(_map(entry, 'segment')['reversed'], 'segment direction'),
    ),
];

/// Checks references, ownership, hierarchy, and counters.
void _checkStructure(GardenDocument d) {
  Never fail(String reason) =>
      throw DocumentFormatError('Damaged file: $reason');

  final placed = <String>{};
  void place(String id) {
    if (!placed.add(id)) fail('a layer appears twice');
  }

  for (final propertyId in d.propertyIds) {
    final property = d.layers[propertyId];
    if (property == null) fail('a property is missing');
    if (property.kind != LayerKind.property || property.parentId != null) {
      fail('a top-level layer is not a property');
    }
    place(propertyId);
  }
  for (final layer in d.layers.values) {
    if (layer.parentId != null) {
      final parent = d.layers[layer.parentId];
      if (parent == null || !parent.children.contains(layer.id)) {
        fail('a layer is missing its parent');
      }
      if (layer.kind.parentKind != parent.kind) {
        fail('a layer is in the wrong place');
      }
    } else if (!d.propertyIds.contains(layer.id)) {
      fail('a layer is not in the drawing');
    }
    for (final childId in layer.children) {
      if (d.layers[childId]?.parentId != layer.id) {
        fail('a child layer is missing');
      }
      place(childId);
    }
    final geometry = d.geometries[layer.geometryId];
    if (geometry == null || geometry.ownerLayerId != layer.id) {
      fail('a layer is missing its drawing');
    }
    if ((layer.kind == LayerKind.zone) != (geometry.dimensions != null)) {
      fail('planting sizes are on the wrong layer');
    }
  }
  if (placed.length != d.layers.length) fail('a layer is not in the drawing');
  final owners = d.layers.values.map((l) => l.geometryId).toSet();
  if (owners.length != d.geometries.length) fail('drawing data is not owned');

  for (final g in d.geometries.values) {
    for (final line in g.lines.values) {
      if (!g.points.containsKey(line.start) ||
          !g.points.containsKey(line.end)) {
        fail('a line is missing a point');
      }
      if (line.start == line.end) fail('a line joins a point to itself');
    }
    final ownedSegments = <String>{};
    for (final shape in g.shapes.values) {
      for (final ring in shape.rings) {
        for (final ref in ring) {
          if (!g.lines.containsKey(ref.segmentId)) {
            fail('a boundary is missing a line');
          }
          if (!ownedSegments.add(ref.segmentId)) {
            fail('a segment belongs to more than one boundary ring');
          }
        }
      }
    }
    for (final circle in g.circles.values) {
      if (!g.points.containsKey(circle.center)) {
        fail('a circle is missing its center');
      }
    }
    for (final (ids, count) in [
      (g.points.keys, g.counters.points),
      (g.lines.keys, g.counters.lines),
      (g.circles.keys, g.counters.circles),
      (g.shapes.keys, g.counters.shapes),
    ]) {
      for (final id in ids) {
        final number = int.tryParse(id.substring(id.lastIndexOf('-') + 1));
        if (number == null || number > count) fail('an ID counter is too low');
      }
    }
    for (final pointId in g.points.keys) {
      if (g.degreeOf(pointId) > 2) fail('a boundary branches');
    }
  }
}

ReferenceImage _referenceFromJson(
  Map<String, Object?> json,
  List<int>? Function(String name)? readAsset,
) {
  final id = _string(json['id'], 'image ID');
  final mimeType = _string(json['mime_type'], 'reference image type');
  if (!['image/png', 'image/jpeg', 'image/webp'].contains(mimeType)) {
    throw const DocumentFormatError('Unsupported reference image type');
  }
  final asset = _string(json['asset'], 'reference image name');
  if (asset != referenceAssetEntry(id, mimeType)) {
    throw const DocumentFormatError('Damaged file: reference image name');
  }
  final bytes = readAsset?.call(asset);
  if (bytes == null) {
    throw const DocumentFormatError(
      'The reference image is missing from this file',
    );
  }
  final data = Uint8List.fromList(bytes);
  if (imageMimeType(data) != mimeType) {
    throw const DocumentFormatError(
      'The reference image in this file is damaged',
    );
  }
  final width = _count(json['pixel_width']);
  final height = _count(json['pixel_height']);
  final scale = _number(json['metres_per_pixel']);
  final opacity = _number(json['opacity']);
  final distance = _optionalNumber(json['known_distance']);
  if (width == 0 || height == 0 || width * height > maxReferencePixels) {
    throw const DocumentFormatError('Damaged file: reference image size');
  }
  if (scale <= 0 || opacity < 0 || opacity > 1 || (distance ?? 0) < 0) {
    throw const DocumentFormatError('Damaged file: reference image settings');
  }
  final start = _optionalVec(json['line_start']);
  final end = _optionalVec(json['line_end']);
  if ((start == null) != (end == null)) {
    throw const DocumentFormatError('Damaged file: reference line');
  }
  return ReferenceImage(
    id: id,
    label: _optionalString(json['label'], 'image name'),
    fileName: _optionalString(json['file_name'], 'image file name'),
    bytes: data,
    mimeType: mimeType,
    pixelWidth: width,
    pixelHeight: height,
    topLeft: _vec(json['top_left']),
    metresPerPixel: scale,
    lineStart: start,
    lineEnd: end,
    knownDistance: distance,
    opacity: opacity,
    locked: _bool(json['locked'], 'reference lock'),
  );
}

Vec _vec(Object? value) {
  final v = _map(value, 'position');
  return Vec(_number(v['x']), _number(v['y']));
}

Vec? _optionalVec(Object? value) => value == null ? null : _vec(value);

// ---------------------------------------------------------------- helpers

Map<String, Object?> _map(Object? value, String what) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw DocumentFormatError('Damaged file: $what is not readable');
}

List<Object?> _list(Object? value, String what) {
  if (value is List) return value;
  throw DocumentFormatError('Damaged file: $what is not readable');
}

List<String> _strings(Object? value, String what) => [
  for (final item in _list(value, what)) _string(item, what),
];

String _string(Object? value, String what) {
  if (value is String && value.isNotEmpty) return value;
  throw DocumentFormatError('Damaged file: $what is not readable');
}

String? _optionalString(Object? value, String what) {
  if (value == null || value is String) return value as String?;
  throw DocumentFormatError('Damaged file: $what is not readable');
}

bool _bool(Object? value, String what) {
  if (value is bool) return value;
  throw DocumentFormatError('Damaged file: $what is not readable');
}

double _number(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  throw const DocumentFormatError('Damaged file: a number is not valid');
}

double? _optionalNumber(Object? value) => value == null ? null : _number(value);

int _count(Object? value) {
  if (value is int && value >= 0) return value;
  throw const DocumentFormatError('Damaged file: a counter is not valid');
}

T _enum<T extends Enum>(List<T> values, Object? name, String what) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw DocumentFormatError('Damaged file: unknown $what "$name"');
}
