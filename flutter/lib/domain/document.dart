import 'geometry.dart';
import 'layer.dart';
import 'reference_image.dart';

typedef IdGenerator = String Function();

/// A complete garden drawing: its layers and their geometry.
///
/// Documents are immutable. Every edit produces a new document, which lets
/// history keep earlier versions without copying unchanged layers.
class GardenDocument {
  GardenDocument({
    required this.id,
    Map<String, Layer> layers = const {},
    Map<String, Geometry> geometries = const {},
    List<String> fields = const [],
    Map<LayerKind, int> nameCounters = const {},
    List<ReferenceImage> references = const [],
    this.imageCounter = 0,
  }) : references = List.unmodifiable(references),
       layers = Map.unmodifiable(layers),
       geometries = Map.unmodifiable(geometries),
       fields = List.unmodifiable(fields),
       nameCounters = Map.unmodifiable(nameCounters);

  final String id;
  final Map<String, Layer> layers;
  final Map<String, Geometry> geometries;

  /// Field layer IDs in creation order.
  final List<String> fields;

  /// Highest automatic name number used for each layer kind.
  final Map<LayerKind, int> nameCounters;

  /// The Reference layer: pictures traced over, drawn under all land.
  /// Bottom first, so later images are drawn on top of earlier ones.
  final List<ReferenceImage> references;

  /// Highest reference image number issued, so IDs are never reused.
  final int imageCounter;

  ReferenceImage? referenceById(String? id) {
    for (final image in references) {
      if (image.id == id) return image;
    }
    return null;
  }

  /// Adds [image] on top of the Reference layer, or replaces the image
  /// with the same ID in place.
  GardenDocument withReferenceImage(ReferenceImage image) {
    final index = references.indexWhere((r) => r.id == image.id);
    final list = [...references];
    if (index < 0) {
      list.add(image);
    } else {
      list[index] = image;
    }
    return _withReferences(list);
  }

  GardenDocument withoutReferenceImage(String id) =>
      _withReferences(references.where((r) => r.id != id).toList());

  /// Moves an image one place up (drawn over more of the others) or down.
  GardenDocument withReferenceMoved(String id, {required bool up}) {
    final index = references.indexWhere((r) => r.id == id);
    final target = index + (up ? 1 : -1);
    if (index < 0 || target < 0 || target >= references.length) return this;
    final list = [...references];
    list.insert(target, list.removeAt(index));
    return _withReferences(list);
  }

  /// An ID for a new reference image: "image-N" past every one issued.
  (GardenDocument, String) nextImageId() {
    final number = imageCounter + 1;
    return (
      GardenDocument(
        id: id,
        layers: layers,
        geometries: geometries,
        fields: fields,
        nameCounters: nameCounters,
        references: references,
        imageCounter: number,
      ),
      'image-$number',
    );
  }

  GardenDocument _withReferences(List<ReferenceImage> list) => GardenDocument(
    id: id,
    layers: layers,
    geometries: geometries,
    fields: fields,
    nameCounters: nameCounters,
    references: list,
    imageCounter: imageCounter,
  );

  Geometry geometryOf(String layerId) =>
      geometries[layers[layerId]!.geometryId]!;

  /// The field this layer is listed under, or null for a field.
  Layer? parentOf(String layerId) => layers[layers[layerId]?.parentId];

  /// The layer whose lock keeps [layerId] from being edited: the layer
  /// itself, or the nearest locked layer it sits inside. Null when the
  /// layer can be edited.
  Layer? lockedBy(String layerId) {
    for (
      Layer? layer = layers[layerId];
      layer != null;
      layer = layers[layer.parentId]
    ) {
      if (layer.locked) return layer;
    }
    return null;
  }

  bool isLocked(String layerId) => lockedBy(layerId) != null;

  /// The layer and every layer inside it, parents before children.
  List<String> subtree(String layerId) => [
    layerId,
    for (final child in layers[layerId]!.children) ...subtree(child),
  ];

  /// Layers in drawing order: each field, then its plots, then its areas.
  /// Worked out once, as the painter and land rules ask for it often.
  late final List<String> drawingOrder = List.unmodifiable([
    for (final id in fields) ...[
      for (final kind in LayerKind.values)
        for (final member in subtree(id))
          if (layers[member]!.kind == kind) member,
    ],
  ]);

  /// The same drawing under a new document identity, as used by Save as.
  GardenDocument withId(String newId) => GardenDocument(
    id: newId,
    layers: layers,
    geometries: geometries,
    fields: fields,
    nameCounters: nameCounters,
    references: references,
    imageCounter: imageCounter,
  );

  GardenDocument copyWith({
    Map<String, Layer>? layers,
    Map<String, Geometry>? geometries,
    List<String>? fields,
    Map<LayerKind, int>? nameCounters,
  }) => GardenDocument(
    id: id,
    layers: layers ?? this.layers,
    geometries: geometries ?? this.geometries,
    fields: fields ?? this.fields,
    nameCounters: nameCounters ?? this.nameCounters,
    references: references,
    imageCounter: imageCounter,
  );

  GardenDocument withGeometry(Geometry geometry) =>
      copyWith(geometries: {...geometries, geometry.id: geometry});

  GardenDocument withLayer(Layer layer) =>
      copyWith(layers: {...layers, layer.id: layer});

  /// Adds an empty layer with the next automatic name.
  ///
  /// Returns the new document and the new layer's ID.
  (GardenDocument, String) addLayer(
    LayerKind kind, {
    String? parentId,
    required IdGenerator newId,
  }) {
    // An area asked for under a plot is listed under that plot's field.
    if (kind == LayerKind.area && layers[parentId]?.kind == LayerKind.plot) {
      parentId = layers[parentId]!.parentId;
    }
    if (kind.homeKind != layers[parentId]?.kind) {
      throw ArgumentError('A ${kind.label} needs a ${kind.homeKind?.label}');
    }
    var counter = nameCounters[kind] ?? 0;
    String name;
    do {
      counter++;
      name = '${kind.label} $counter';
    } while (layers.values.any((l) => l.kind == kind && l.name == name));

    final layer = Layer(
      id: newId(),
      kind: kind,
      name: name,
      parentId: parentId,
      geometryId: newId(),
      properties: LayerProperties.defaultsFor(kind),
    );
    final geometry = Geometry(
      id: layer.geometryId,
      ownerLayerId: layer.id,
      dimensions: kind == LayerKind.area ? const AreaDimensions() : null,
    );
    final updatedLayers = {...layers, layer.id: layer};
    if (parentId != null) {
      final parent = layers[parentId]!;
      updatedLayers[parentId] = parent.copyWith(
        children: [...parent.children, layer.id],
      );
    }
    final document = copyWith(
      layers: updatedLayers,
      geometries: {...geometries, geometry.id: geometry},
      fields: parentId == null ? [...fields, layer.id] : fields,
      nameCounters: {...nameCounters, kind: counter},
    );
    return (document, layer.id);
  }

  /// Removes a layer together with every layer inside it.
  GardenDocument removeLayer(String layerId) {
    final removed = subtree(layerId).toSet();
    final layer = layers[layerId]!;
    final updatedLayers = {
      for (final entry in layers.entries)
        if (!removed.contains(entry.key)) entry.key: entry.value,
    };
    if (layer.parentId != null) {
      final parent = layers[layer.parentId]!;
      updatedLayers[parent.id] = parent.copyWith(
        children: parent.children.where((id) => id != layerId).toList(),
      );
    }
    final removedGeometry = removed.map((id) => layers[id]!.geometryId).toSet();
    return copyWith(
      layers: updatedLayers,
      geometries: {
        for (final entry in geometries.entries)
          if (!removedGeometry.contains(entry.key)) entry.key: entry.value,
      },
      fields: fields.where((id) => id != layerId).toList(),
    );
  }

  /// Raises every ID counter to at least the values in [other], so numbers
  /// issued in [other] are never issued again.
  GardenDocument withCountersFrom(GardenDocument other) =>
      withCounterFloor(CounterLedger()..record(other));

  /// Raises every ID counter to at least the highest value in [ledger].
  GardenDocument withCounterFloor(CounterLedger ledger) {
    var changed = false;
    final names = {...nameCounters};
    ledger.names.forEach((kind, value) {
      if (value > (names[kind] ?? 0)) {
        names[kind] = value;
        changed = true;
      }
    });
    var images = imageCounter;
    if (ledger.images > images) {
      images = ledger.images;
      changed = true;
    }
    final updated = {...geometries};
    for (final entry in geometries.entries) {
      final known = ledger.geometry[entry.key];
      if (known == null) continue;
      final raised = entry.value.counters.atLeast(known);
      if (!raised.sameAs(entry.value.counters)) {
        updated[entry.key] = entry.value.copyWith(counters: raised);
        changed = true;
      }
    }
    if (!changed) return this;
    return GardenDocument(
      id: id,
      layers: layers,
      geometries: updated,
      fields: fields,
      nameCounters: names,
      references: references,
      imageCounter: images,
    );
  }
}

/// The highest ID and name numbers ever issued, per geometry and layer kind.
///
/// Kept outside the document so Undo, which restores older documents, never
/// lets a number be issued twice.
class CounterLedger {
  final Map<String, IdCounters> geometry = {};
  final Map<LayerKind, int> names = {};

  /// Highest reference image number issued.
  int images = 0;

  /// Takes the higher of each number here and in [other].
  void merge(CounterLedger other) {
    other.geometry.forEach((id, counters) {
      final known = geometry[id];
      geometry[id] = known == null ? counters : known.atLeast(counters);
    });
    other.names.forEach((kind, value) {
      if (value > (names[kind] ?? 0)) names[kind] = value;
    });
    if (other.images > images) images = other.images;
  }

  void record(GardenDocument document) {
    for (final entry in document.geometries.entries) {
      final known = geometry[entry.key];
      geometry[entry.key] = known == null
          ? entry.value.counters
          : known.atLeast(entry.value.counters);
    }
    document.nameCounters.forEach((kind, value) {
      if (value > (names[kind] ?? 0)) names[kind] = value;
    });
    if (document.imageCounter > images) images = document.imageCounter;
  }
}
