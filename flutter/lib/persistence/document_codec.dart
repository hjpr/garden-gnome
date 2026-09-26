import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../domain/document.dart';
import '../domain/geometry.dart';
import '../domain/layer.dart';
import '../domain/reference_image.dart';
import '../domain/vec.dart';

// Version 2 adds curved edges and hole rings. Older readers must refuse it
// rather than silently opening a chord-only drawing with filled-in holes.
// Version 3 makes every closed shape on a layer part of its land, keeps
// the shape stack order and labels, moves patterns into layer properties,
// and lists areas under their field. Version 2 files are converted on open.
// Version 4 adds the reference image, stored as its own file in the ZIP.
// A version 3 reader would silently drop it, so it must refuse the file.
// Version 5 holds any number of reference images in the Reference layer,
// each with its own ID, name, scale and reference line. Version 4 files
// (one image) are converted on open.
const int schemaVersion = 5;
const String formatName = 'garden-gnome';
const String documentEntry = 'document.json';

const int _maxCompressedBytes = 100 * 1024 * 1024;
const int _maxDocumentBytes = 16 * 1024 * 1024;

/// Where a reference picture is kept inside the ZIP, by ID and type.
String _referenceEntry(String id, String mimeType) =>
    'assets/$id.${mimeType.split('/').last}';

/// Where a version 4 file kept its one picture.
String _oldReferenceEntry(String mimeType) =>
    'assets/reference.${mimeType.split('/').last}';

/// Raised when a file cannot be opened. The message is shown to the user.
class DocumentFormatError implements Exception {
  const DocumentFormatError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Packs a drawing into a portable .ggnome file (a ZIP with document.json).
Uint8List encodeGgnome(GardenDocument document) {
  final json = utf8.encode(jsonEncode(documentToJson(document)));
  final archive = Archive()..add(ArchiveFile.bytes(documentEntry, json));
  for (final image in document.references) {
    archive.add(
      ArchiveFile.bytes(_referenceEntry(image.id, image.mimeType), image.bytes),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Reads a .ggnome file, checking it completely before returning it.
GardenDocument decodeGgnome(Uint8List bytes) {
  if (bytes.length > _maxCompressedBytes) {
    throw const DocumentFormatError('This file is too large to open');
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: true);
  } catch (_) {
    throw const DocumentFormatError('This is not a Garden Gnome file');
  }
  final names = <String>{};
  final files = <String, ArchiveFile>{};
  ArchiveFile? entry;
  for (final file in archive.files) {
    final name = file.name;
    if (!names.add(name)) {
      throw const DocumentFormatError('The file has duplicate entries');
    }
    if (name.startsWith('/') || name.split('/').contains('..')) {
      throw const DocumentFormatError('The file has unsafe entries');
    }
    if (name == documentEntry) entry = file;
    files[name] = file;
  }
  if (entry == null) {
    throw const DocumentFormatError('The file has no drawing in it');
  }
  if (entry.size > _maxDocumentBytes) {
    throw const DocumentFormatError('The drawing inside the file is too large');
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(entry.readBytes()!));
  } catch (_) {
    throw const DocumentFormatError('The drawing inside the file is damaged');
  }
  return documentFromJson(
    json,
    readAsset: (name) {
      final file = files[name];
      if (file == null) return null;
      if (file.size > maxReferenceBytes) {
        throw const DocumentFormatError('The reference image is too large');
      }
      return file.readBytes();
    },
  );
}

// ---------------------------------------------------------------- writing

Map<String, Object?> documentToJson(GardenDocument d) => {
  'format': formatName,
  'schema_version': schemaVersion,
  'document_id': d.id,
  'fields': d.fields,
  'name_counters': {
    for (final entry in d.nameCounters.entries) entry.key.name: entry.value,
  },
  'layers': {
    for (final layer in d.layers.values) layer.id: _layerToJson(layer),
  },
  'geometries': {for (final g in d.geometries.values) g.id: _geometryToJson(g)},
  'image_counter': d.imageCounter,
  'references': [for (final image in d.references) _referenceToJson(image)],
};

Map<String, Object?> _referenceToJson(ReferenceImage image) => {
  'id': image.id,
  'label': image.label,
  'file_name': image.fileName,
  'asset': _referenceEntry(image.id, image.mimeType),
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
    FieldProperties p => {
      'color': p.color.name,
      'pattern': p.pattern?.name,
      'drainage': p.drainage?.name,
      'soil': {
        'ph': p.soil.ph,
        'phosphorus': p.soil.phosphorus,
        'potassium': p.soil.potassium,
        'calcium': p.soil.calcium,
        'magnesium': p.soil.magnesium,
        'cation_exchange': p.soil.cationExchange,
        'conductivity': p.soil.conductivity,
        'organic_matter': p.soil.organicMatter,
      },
    },
    PlotProperties p => {
      'color': p.color.name,
      'pattern': p.pattern?.name,
      'ground': p.ground,
    },
    AreaProperties p => {
      'planting_type': p.plantingType.name,
      'crop': p.crop,
      'pattern': p.pattern?.name,
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
      l.id: {'start': l.start, 'end': l.end, 'bulge': l.bulge},
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
/// a plot outside its field) is not damage; it opens and is shown invalid,
/// just as it was when saved.
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
  if (version is! int || version > schemaVersion) {
    throw const DocumentFormatError(
      'This file was made by a newer version of Garden Gnome',
    );
  }

  if (version < 1) {
    throw const DocumentFormatError('Damaged file: unsupported schema version');
  }

  var layers = <String, Layer>{};
  _map(root['layers'], 'layers').forEach((id, value) {
    layers[id] = _layerFromJson(id, _map(value, 'layer'));
  });
  final geometries = <String, Geometry>{};
  final oldPatterns = <String, String>{};
  _map(root['geometries'], 'geometries').forEach((id, value) {
    final json = _map(value, 'geometry');
    geometries[id] = _geometryFromJson(id, json, version);
    if (version < 3) {
      if (_oldBoundaryPattern(json) case final pattern?) {
        oldPatterns[id] = pattern;
      }
    }
  });
  if (version < 3) layers = _upgradeLayers(layers, oldPatterns);

  final references = <ReferenceImage>[];
  var imageCounter = 0;
  if (version >= 5) {
    for (final item in _list(root['references'] ?? const [], 'references')) {
      references.add(_referenceFromJson(_map(item, 'reference'), readAsset));
    }
    imageCounter = _count(root['image_counter'] ?? 0);
  } else if (root['reference'] != null) {
    // A version 4 drawing had one picture; it becomes Image 1.
    references.add(
      _referenceFromJson(
        _map(root['reference'], 'reference'),
        readAsset,
        legacyId: 'image-1',
      ),
    );
    imageCounter = 1;
  }
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

  final nameCounters = <LayerKind, int>{};
  _map(root['name_counters'] ?? const {}, 'name counters').forEach((k, v) {
    nameCounters[_enum(LayerKind.values, k, 'layer kind')] = _count(v);
  });

  final document = GardenDocument(
    id: _string(root['document_id'], 'document ID'),
    layers: layers,
    geometries: geometries,
    fields: _strings(root['fields'], 'fields'),
    nameCounters: nameCounters,
    references: references,
    imageCounter: imageCounter,
  );
  _checkStructure(document);
  return document;
}

Layer _layerFromJson(String id, Map<String, Object?> json) {
  final kind = _enum(LayerKind.values, json['kind'], 'layer kind');
  final props = _map(json['properties'] ?? const {}, 'properties');
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
    parentId: _optionalString(json['parent_id']),
    children: _strings(json['children'] ?? const [], 'children'),
    geometryId: _string(json['geometry_id'], 'geometry ID'),
    // Files saved before locking existed have no value: unlocked.
    locked: _optionalBool(json['locked'], 'layer lock') ?? false,
    properties: switch (kind) {
      LayerKind.field => FieldProperties(
        color: _enum(OutlineColor.values, props['color'] ?? 'green', 'color'),
        pattern: _pattern(props['pattern']),
        drainage: props['drainage'] == null
            ? null
            : _enum(SoilDrainage.values, props['drainage'], 'drainage'),
        soil: _soilFromJson(_map(props['soil'] ?? const {}, 'soil')),
      ),
      LayerKind.plot => PlotProperties(
        color: _enum(OutlineColor.values, props['color'] ?? 'sage', 'color'),
        pattern: _pattern(props['pattern']),
        ground: _optionalString(props['ground']),
      ),
      LayerKind.area => AreaProperties(
        plantingType: _enum(
          PlantingType.values,
          props['planting_type'] ?? 'flat',
          'planting type',
        ),
        crop: _optionalString(props['crop']),
        pattern: _pattern(props['pattern']),
      ),
    },
  );
}

FillPattern? _pattern(Object? name) =>
    name == null ? null : _enum(FillPattern.values, name, 'pattern');

/// A version 2 layer kept its Field or Area pattern on its boundary.
String? _oldBoundaryPattern(Map<String, Object?> json) {
  final boundary = json['boundary'];
  if (boundary == null) return null;
  final b = _map(boundary, 'boundary');
  final registry = b['kind'] == 'circle' ? 'circles' : 'shapes';
  final records = _map(json[registry] ?? const {}, registry);
  final record = records[b['id']];
  if (record == null) return null;
  return _optionalString(_map(record, 'boundary')['pattern']);
}

/// Converts version 2 layers: patterns move into Properties, and areas
/// are listed under their plot's field rather than under the plot.
Map<String, Layer> _upgradeLayers(
  Map<String, Layer> layers,
  Map<String, String> patterns,
) {
  final result = {...layers};
  for (final layer in layers.values) {
    final pattern = FillPattern.fromName(patterns[layer.geometryId]);
    if (pattern != null && layer.properties is! PlotProperties) {
      result[layer.id] = result[layer.id]!.copyWith(
        properties: layer.properties.withPattern(pattern),
      );
    }
  }
  for (final area in layers.values.where((l) => l.kind == LayerKind.area)) {
    final plot = layers[area.parentId];
    final fieldId = plot?.parentId;
    if (plot == null || fieldId == null || result[fieldId] == null) continue;
    final current = result[area.id]!;
    result[area.id] = Layer(
      id: current.id,
      kind: current.kind,
      name: current.name,
      parentId: fieldId,
      children: current.children,
      geometryId: current.geometryId,
      properties: current.properties,
      locked: current.locked,
    );
    final oldParent = result[plot.id]!;
    result[plot.id] = oldParent.copyWith(
      children: oldParent.children.where((id) => id != area.id).toList(),
    );
    final field = result[fieldId]!;
    result[fieldId] = field.copyWith(children: [...field.children, area.id]);
  }
  return result;
}

SoilSample _soilFromJson(Map<String, Object?> json) => SoilSample(
  ph: _optionalNumber(json['ph']),
  phosphorus: _optionalNumber(json['phosphorus']),
  potassium: _optionalNumber(json['potassium']),
  calcium: _optionalNumber(json['calcium']),
  magnesium: _optionalNumber(json['magnesium']),
  cationExchange: _optionalNumber(json['cation_exchange']),
  conductivity: _optionalNumber(json['conductivity']),
  organicMatter: _optionalNumber(json['organic_matter']),
);

Geometry _geometryFromJson(String id, Map<String, Object?> json, int version) {
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
      bulge: l['bulge'] == null ? 0 : _number(l['bulge']),
    );
  });
  final circles = <String, Circle>{};
  _map(json['circles'] ?? const {}, 'circles').forEach((circleId, value) {
    final c = _map(value, 'circle');
    final radius = _number(c['radius']);
    if (radius <= 0) {
      throw const DocumentFormatError('Damaged file: a circle has no size');
    }
    circles[circleId] = Circle(
      circleId,
      _string(c['center'], 'circle center'),
      radius,
      label: _optionalString(c['label']),
    );
  });
  final shapes = <String, ClosedShape>{};
  _map(json['shapes'], 'shapes').forEach((shapeId, value) {
    final s = _map(value, 'shape');
    shapes[shapeId] = ClosedShape(
      shapeId,
      _ringFromJson(s['segments']),
      holes: [
        for (final ring in _list(s['holes'] ?? const [], 'holes'))
          _ringFromJson(ring),
      ],
      label: _optionalString(s['label']),
    );
  });
  final order = <String>[];
  if (version >= 3) {
    order.addAll(_strings(json['order'] ?? const [], 'shape order'));
    for (final item in order) {
      if (!shapes.containsKey(item) && !circles.containsKey(item)) {
        throw const DocumentFormatError('Damaged file: a shape is missing');
      }
    }
    if (order.toSet().length != order.length) {
      throw const DocumentFormatError('Damaged file: a shape appears twice');
    }
  } else if (json['boundary'] != null) {
    // The old boundary goes to the bottom; former Boolean operands sit
    // above it, in the order they were drawn.
    final b = _map(json['boundary'], 'boundary');
    final boundaryId = _string(b['id'], 'boundary ID');
    final registry = switch (b['kind']) {
      'shape' => shapes,
      'circle' => circles,
      _ => throw const DocumentFormatError('Unsupported boundary type'),
    };
    if (!registry.containsKey(boundaryId)) {
      throw const DocumentFormatError('Damaged file: a boundary is missing');
    }
    order.add(boundaryId);
  }
  // A version 2 layer kept an empty record where a boundary was deleted.
  shapes.removeWhere(
    (shapeId, shape) =>
        version < 3 && shape.rings.every((ring) => ring.isEmpty),
  );
  order.removeWhere(
    (item) => !shapes.containsKey(item) && !circles.containsKey(item),
  );
  final last = _map(json['last_ids'] ?? const {}, 'counters');
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
      points: _count(last['points'] ?? 0),
      lines: _count(last['lines'] ?? 0),
      circles: _count(last['circles'] ?? 0),
      shapes: _count(last['shapes'] ?? 0),
    ),
    dimensions: dims == null
        ? null
        : AreaDimensions(
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
      reversed:
          _optionalBool(
            _map(entry, 'segment')['reversed'],
            'segment direction',
          ) ??
          false,
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

  for (final fieldId in d.fields) {
    final field = d.layers[fieldId];
    if (field == null) fail('a field is missing');
    if (field.kind != LayerKind.field || field.parentId != null) {
      fail('a top-level layer is not a field');
    }
    place(fieldId);
  }
  for (final layer in d.layers.values) {
    if (layer.parentId != null) {
      final parent = d.layers[layer.parentId];
      if (parent == null || !parent.children.contains(layer.id)) {
        fail('a layer is missing its parent');
      }
      if (layer.kind.homeKind != parent.kind) {
        fail('a layer is in the wrong place');
      }
    } else if (!d.fields.contains(layer.id)) {
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
  List<int>? Function(String name)? readAsset, {
  String? legacyId,
}) {
  final id = legacyId ?? _string(json['id'], 'image ID');
  final mimeType = _string(json['mime_type'], 'reference image type');
  if (!['image/png', 'image/jpeg', 'image/webp'].contains(mimeType)) {
    throw const DocumentFormatError('Unsupported reference image type');
  }
  final asset = _string(json['asset'], 'reference image name');
  final expected = legacyId == null
      ? _referenceEntry(id, mimeType)
      : _oldReferenceEntry(mimeType);
  if (asset != expected) {
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
  final opacity = _number(json['opacity'] ?? 0.6);
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
    label: _optionalString(json['label']),
    fileName: _optionalString(json['file_name']),
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
    locked: _optionalBool(json['locked'], 'reference lock') ?? false,
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

String? _optionalString(Object? value) => value is String ? value : null;

bool? _optionalBool(Object? value, String what) {
  if (value == null || value is bool) return value as bool?;
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
