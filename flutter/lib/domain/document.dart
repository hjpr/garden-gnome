import 'feature.dart';
import 'geometry.dart';
import 'grow/climate.dart';
import 'grow/planting.dart';
import 'layer.dart';
import 'reference_image.dart';

typedef IdGenerator = String Function();

/// A farm: its land (layers and their geometry), its climate, and what
/// is planted on it. The open document is the farm every tool works on.
///
/// Documents are immutable. Every edit produces a new document, which lets
/// history keep earlier versions without copying unchanged layers.
class GardenDocument {
  GardenDocument({
    required this.id,
    Map<String, Layer> layers = const {},
    Map<String, Geometry> geometries = const {},
    List<String> propertyIds = const [],
    Map<LayerKind, int> nameCounters = const {},
    List<ReferenceImage> references = const [],
    bool referenceLayer = false,
    this.imageCounter = 0,
    List<Feature> features = const [],
    this.featureCounter = 0,
    this.climate = const Climate(),
    Map<String, Planting> plantings = const {},
    this.plantingCounter = 0,
  }) : plantings = Map.unmodifiable(plantings),
       hasReferenceLayer = referenceLayer || references.isNotEmpty,
       references = List.unmodifiable(references),
       features = List.unmodifiable(features),
       layers = Map.unmodifiable(layers),
       geometries = Map.unmodifiable(geometries),
       propertyIds = List.unmodifiable(propertyIds),
       nameCounters = Map.unmodifiable(nameCounters);

  /// Hardiness zone and frost dates where the farm is.
  final Climate climate;

  /// Every sowing on this farm, from greenhouse tray to harvest.
  final Map<String, Planting> plantings;

  /// Highest planting number issued, so IDs are never reused.
  final int plantingCounter;

  GardenDocument withClimate(Climate next) => _rebuild(climate: next);

  GardenDocument withPlanting(Planting p) =>
      _rebuild(plantings: {...plantings, p.id: p});

  GardenDocument withoutPlanting(String id) =>
      _rebuild(plantings: {...plantings}..remove(id));

  /// An ID for a new planting: "planting-N" past every one issued.
  (GardenDocument, String) nextPlantingId() {
    final number = plantingCounter + 1;
    return (_rebuild(plantingCounter: number), 'planting-$number');
  }

  /// Raised beds, greenhouses and high tunnels, drawn over all land in
  /// this order (later ones on top).
  final List<Feature> features;

  /// Highest feature number issued, so IDs are never reused.
  final int featureCounter;

  Feature? featureById(String? id) {
    for (final feature in features) {
      if (feature.id == id) return feature;
    }
    return null;
  }

  /// Adds [feature] on top, or replaces the feature with the same ID in
  /// place.
  GardenDocument withFeature(Feature feature) {
    final list = [...features];
    final index = list.indexWhere((f) => f.id == feature.id);
    index < 0 ? list.add(feature) : list[index] = feature;
    return _rebuild(features: list);
  }

  GardenDocument withoutFeature(String id) =>
      _rebuild(features: features.where((f) => f.id != id).toList());

  /// An ID for a new feature: "feature-N" past every one issued.
  (GardenDocument, String) nextFeatureId() {
    final number = featureCounter + 1;
    return (_rebuild(featureCounter: number), 'feature-$number');
  }

  /// This document with the given parts replaced; everything else kept.
  GardenDocument _rebuild({
    String? id,
    Map<String, Layer>? layers,
    Map<String, Geometry>? geometries,
    List<String>? propertyIds,
    Map<LayerKind, int>? nameCounters,
    List<ReferenceImage>? references,
    bool? referenceLayer,
    int? imageCounter,
    List<Feature>? features,
    int? featureCounter,
    Climate? climate,
    Map<String, Planting>? plantings,
    int? plantingCounter,
  }) => GardenDocument(
    id: id ?? this.id,
    layers: layers ?? this.layers,
    geometries: geometries ?? this.geometries,
    propertyIds: propertyIds ?? this.propertyIds,
    nameCounters: nameCounters ?? this.nameCounters,
    references: references ?? this.references,
    referenceLayer: referenceLayer ?? hasReferenceLayer,
    imageCounter: imageCounter ?? this.imageCounter,
    features: features ?? this.features,
    featureCounter: featureCounter ?? this.featureCounter,
    climate: climate ?? this.climate,
    plantings: plantings ?? this.plantings,
    plantingCounter: plantingCounter ?? this.plantingCounter,
  );

  final String id;
  final Map<String, Layer> layers;
  final Map<String, Geometry> geometries;

  /// Property layer IDs in creation order.
  final List<String> propertyIds;

  /// Highest automatic name number used for each layer kind.
  final Map<LayerKind, int> nameCounters;

  /// The Reference layer: pictures traced over, drawn under all land.
  /// Bottom first, so later images are drawn on top of earlier ones.
  final List<ReferenceImage> references;

  /// Whether the drawing has a Reference layer. It can be empty: it stays
  /// when its last image is removed, until the layer itself is deleted.
  final bool hasReferenceLayer;

  /// Adds an empty Reference layer.
  GardenDocument withReferenceLayer() =>
      hasReferenceLayer ? this : _rebuild(referenceLayer: true);

  /// Removes the Reference layer and every image in it.
  GardenDocument withoutReferenceLayer() => hasReferenceLayer
      ? _rebuild(references: const [], referenceLayer: false)
      : this;

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
    return (_rebuild(imageCounter: number), 'image-$number');
  }

  GardenDocument _withReferences(List<ReferenceImage> list) =>
      _rebuild(references: list);

  Geometry geometryOf(String layerId) =>
      geometries[layers[layerId]!.geometryId]!;

  /// The property this layer is listed under, or null for a property.
  Layer? parentOf(String layerId) => layers[layers[layerId]?.parentId];

  /// The layer whose lock keeps [layerId] from being edited: the layer
  /// itself, or the property it is listed under. Null when the layer can
  /// be edited.
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

  /// The layer and, for a property, its zones: the property first.
  List<String> subtree(String layerId) => [
    layerId,
    for (final child in layers[layerId]!.children) ...subtree(child),
  ];

  /// Layers in drawing order: each property, then its zones in creation
  /// order, so a later zone is drawn over an earlier one. Worked out once,
  /// as the painter and land rules ask for it often.
  late final List<String> drawingOrder = List.unmodifiable([
    for (final id in propertyIds) ...[
      for (final kind in LayerKind.values)
        for (final member in subtree(id))
          if (layers[member]!.kind == kind) member,
    ],
  ]);

  /// The same drawing under a new document identity, as used by Save as.
  GardenDocument withId(String newId) => _rebuild(id: newId);

  GardenDocument copyWith({
    Map<String, Layer>? layers,
    Map<String, Geometry>? geometries,
    List<String>? propertyIds,
    Map<LayerKind, int>? nameCounters,
  }) => _rebuild(
    layers: layers,
    geometries: geometries,
    propertyIds: propertyIds,
    nameCounters: nameCounters,
  );

  GardenDocument withGeometry(Geometry geometry) =>
      copyWith(geometries: {...geometries, geometry.id: geometry});

  GardenDocument withLayer(Layer layer) =>
      copyWith(layers: {...layers, layer.id: layer});

  /// Adds an empty layer with the next automatic name.
  ///
  /// [role] names it ("Bed 3") and gives its starting settings; without
  /// it the layer is named after its kind with that kind's defaults.
  /// Returns the new document and the new layer's ID.
  (GardenDocument, String) addLayer(
    LayerKind kind, {
    String? parentId,
    required IdGenerator newId,
    LayerRole? role,
  }) {
    if (kind.parentKind != layers[parentId]?.kind ||
        (role != null && role.kind != kind)) {
      throw ArgumentError('A ${kind.label} needs a ${kind.parentKind?.label}');
    }
    final prefix = role?.label ?? kind.label;
    var counter = nameCounters[kind] ?? 0;
    String name;
    if (role != null && role != LayerRole.property) {
      // Beds and plantings share the zone counter, so each is numbered on
      // its own, after the highest of its kind in the drawing.
      var highest = 0;
      for (final layer in layers.values) {
        if (!layer.name.startsWith('$prefix ')) continue;
        final number = int.tryParse(layer.name.substring(prefix.length + 1));
        if (number != null && number > highest) highest = number;
      }
      name = '$prefix ${highest + 1}';
      counter++;
    } else {
      do {
        counter++;
        name = '$prefix $counter';
      } while (layers.values.any((l) => l.kind == kind && l.name == name));
    }

    final layer = Layer(
      id: newId(),
      kind: kind,
      name: name,
      parentId: parentId,
      geometryId: newId(),
      properties: role?.defaults ?? LayerProperties.defaultsFor(kind),
    );
    final geometry = Geometry(
      id: layer.geometryId,
      ownerLayerId: layer.id,
      dimensions: kind == LayerKind.zone ? const PlantingDimensions() : null,
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
      propertyIds: parentId == null ? [...propertyIds, layer.id] : propertyIds,
      nameCounters: {...nameCounters, kind: counter},
    );
    return (document, layer.id);
  }

  /// Removes a layer, and a property's zones with it.
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
      propertyIds: propertyIds.where((id) => id != layerId).toList(),
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
    var featureNumbers = featureCounter;
    if (ledger.features > featureNumbers) {
      featureNumbers = ledger.features;
      changed = true;
    }
    var plantingNumbers = plantingCounter;
    if (ledger.plantings > plantingNumbers) {
      plantingNumbers = ledger.plantings;
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
    return _rebuild(
      geometries: updated,
      nameCounters: names,
      imageCounter: images,
      featureCounter: featureNumbers,
      plantingCounter: plantingNumbers,
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

  /// Highest feature number issued.
  int features = 0;

  /// Highest planting number issued.
  int plantings = 0;

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
    if (other.features > features) features = other.features;
    if (other.plantings > plantings) plantings = other.plantings;
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
    if (document.featureCounter > features) {
      features = document.featureCounter;
    }
    if (document.plantingCounter > plantings) {
      plantings = document.plantingCounter;
    }
  }
}
