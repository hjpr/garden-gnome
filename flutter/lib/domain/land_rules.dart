import 'document.dart';
import 'geometry.dart';
import 'geometry_rules.dart';
import 'layer.dart';
import 'planar.dart';
import 'region.dart';

/// The rules between layers, reported as a status rather than enforced.
///
/// Nothing a user draws is refused for breaking these rules. A layer that
/// breaks one is kept but marked invalid, and invalid land never counts as
/// active. The status is worked out from the drawing itself, so it is
/// always current after any edit, Undo, or file open.
///
/// A layer is a group of shapes, and every layer must be finished: each
/// outline closed and sound, with no loose lines or points. A property must
/// also stand alone: no two of its shapes overlap, and it overlaps no other
/// property. A zone must stay within the property it belongs to, drawing
/// in progress included. Inside it, zone shapes may overlap and touch each
/// other and other zones.
extension LandStatus on GardenDocument {
  /// Why [layerId] is not valid land, or null when it is. Unfinished
  /// drawing (open outlines, loose lines or points) counts as a problem.
  String? problemOf(String layerId) =>
      ruleProblemOf(layerId) ?? _unfinishedOf(layerId);

  /// Why [layerId] breaks a drawing rule, ignoring unfinished drawing.
  /// Previews use this, so a shape being drawn is not shown as a mistake.
  String? ruleProblemOf(String layerId) {
    final cache = _problemCache[this] ??= {};
    return cache.putIfAbsent(layerId, () => _findProblem(this, layerId));
  }

  bool isValid(String layerId) => problemOf(layerId) == null;

  /// Why the layer does not count as real land yet, or null when it does.
  /// Land counts once it has a closed shape and is valid, and a zone only
  /// while its property counts too.
  String? inactiveReason(String layerId) {
    final layer = layers[layerId];
    if (layer == null) return 'Layer not found';
    final problem = problemOf(layerId);
    if (problem != null) return problem;
    if (!geometryOf(layerId).isClosed) return 'No closed shape yet';
    final property = layers[layer.parentId];
    if (property != null && !isActive(property.id)) {
      return '${property.name} is not active';
    }
    return null;
  }

  bool isActive(String layerId) => inactiveReason(layerId) == null;

  /// The layer's land area in square metres, or null while it has none.
  /// A zone's shapes may overlap, so shared land is counted once. On a
  /// property an overlap is a mistake: each shape counts in full until the
  /// shapes are combined.
  double? netAreaOf(String layerId) {
    final geometry = geometryOf(layerId);
    return layers[layerId]!.kind.exclusive
        ? geometry.area
        : geometry.coveredArea;
  }

  /// Whether closed shape [shapeId] of zone [layerId] lies outside the
  /// property the zone belongs to. Always false for a property's shapes.
  bool isOutsideProperty(String layerId, String shapeId) {
    final property = layers[layers[layerId]?.parentId];
    final shape = geometryOf(layerId).regionOf(shapeId);
    if (property == null || shape == null) return false;
    final land = geometryOf(property.id).region;
    return land == null || !land.contains(shape);
  }

  /// Layers that are invalid here but were valid (or absent) in [before],
  /// with the reason for each, in drawing order. Unfinished drawing is not
  /// counted: it is the normal state while a shape is being drawn.
  Map<String, String> newProblemsSince(GardenDocument before) => {
    for (final id in drawingOrder)
      if (ruleProblemOf(id) case final problem?)
        if (!before.layers.containsKey(id) || before.ruleProblemOf(id) == null)
          id: problem,
  };

  String? _unfinishedOf(String layerId) {
    if (!layers.containsKey(layerId)) return null;
    return geometryOf(layerId).unfinishedReason;
  }
}

/// Documents are immutable, so a layer's status can be remembered for the
/// life of the document it was worked out for.
final _problemCache = Expando<Map<String, String?>>('layer problems');

String? _findProblem(GardenDocument document, String layerId) {
  if (!document.layers.containsKey(layerId)) return null;
  final layer = document.layers[layerId]!;
  final geometry = document.geometryOf(layerId);
  final exclusive = layer.kind.exclusive;
  final ownProblem = geometryProblem(geometry, shapesMayMeet: !exclusive);
  if (ownProblem != null) return ownProblem;
  if (!exclusive) return _outsideProblem(document, layer, geometry);

  final ids = geometry.closedIds;
  final regions = {for (final id in ids) id: geometry.regionOf(id)!};
  for (var i = 0; i < ids.length; i++) {
    for (var j = 0; j < i; j++) {
      if (regions[ids[i]]!.overlaps(regions[ids[j]]!)) {
        return '${geometry.labelOf(ids[i])} overlaps '
            '${geometry.labelOf(ids[j])}. Union them, or move one';
      }
    }
  }

  final region = geometry.region;
  if (region != null) {
    for (final otherId in document.drawingOrder) {
      final other = document.layers[otherId]!;
      if (otherId == layerId || other.kind != layer.kind) continue;
      final land = document.geometryOf(otherId).region;
      if (land != null && region.overlaps(land)) {
        return 'Overlaps ${other.name}';
      }
    }
  }
  return null;
}

/// Why a zone's drawing strays outside the property it belongs to, or null
/// when it all lies within. Unfinished drawing counts too, so a stroke that
/// leaves the property turns red while it is drawn.
String? _outsideProblem(
  GardenDocument document,
  Layer zone,
  Geometry geometry,
) {
  final property = document.layers[zone.parentId];
  if (property == null) return null;
  for (final id in geometry.closedIds) {
    if (document.isOutsideProperty(zone.id, id)) {
      return '${geometry.labelOf(id)} is not inside ${property.name}';
    }
  }
  // Until the property has land, there is nothing for a stroke to leave.
  final land = document.geometryOf(property.id).region;
  if (land != null && !_constructionInside(land, geometry)) {
    return 'Drawing is not inside ${property.name}';
  }
  return null;
}

/// Whether unfinished drawing (lines and points not yet part of a closed
/// shape) lies inside [land].
bool _constructionInside(Region land, Geometry geometry) {
  final closed = geometry.closedIds.toSet();
  final covered = geometry.definingPoints(closed);
  final coveredEdges = {
    for (final id in closed)
      for (final ring in geometry.shapes[id]?.rings ?? <List<SegmentRef>>[])
        for (final ref in ring) ref.segmentId,
  };
  for (final line in geometry.lines.values) {
    if (coveredEdges.contains(line.id)) continue;
    if (!line.edges(geometry.points).every(land.containsEdge)) return false;
    covered.addAll([line.start, line.end]);
  }
  for (final entry in geometry.points.entries) {
    if (covered.contains(entry.key)) continue;
    if (land.locate(entry.value) == PointLocation.outside) return false;
  }
  return true;
}
