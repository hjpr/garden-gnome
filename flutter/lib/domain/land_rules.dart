import 'document.dart';
import 'geometry.dart';
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
/// A layer is a group of shapes. The group is valid only when every shape
/// is: each is closed, no two overlap, each sits inside a layer of the
/// kind above (any field for a plot, any plot for an area), and none
/// overlaps another layer of the same kind.
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
  ///
  /// Land counts once it has a closed shape, it breaks no rule, and every
  /// layer its shapes sit inside counts too.
  String? inactiveReason(String layerId) {
    final cache = _inactiveCache[this] ??= {};
    return cache.containsKey(layerId)
        ? cache[layerId]
        : cache[layerId] = _findInactiveReason(layerId);
  }

  String? _findInactiveReason(String layerId) {
    if (!layers.containsKey(layerId)) return 'Layer not found';
    final problem = problemOf(layerId);
    if (problem != null) return problem;
    final geometry = geometryOf(layerId);
    if (!geometry.isClosed) return 'No closed shape yet';
    for (final shapeId in geometry.closedIds) {
      final container = containerOf(layerId, shapeId);
      if (container != null && !isActive(container)) {
        return '${layers[container]!.name} is not active';
      }
    }
    return null;
  }

  bool isActive(String layerId) => inactiveReason(layerId) == null;

  /// The layer of the kind above whose land holds [shapeId], or null for
  /// a field or a shape that is outside every such layer.
  String? containerOf(String layerId, String shapeId) {
    final kind = layers[layerId]?.kind.parentKind;
    if (kind == null) return null;
    final region = geometryOf(layerId).regionOf(shapeId);
    if (region == null) return null;
    for (final id in drawingOrder) {
      if (layers[id]!.kind != kind) continue;
      final land = geometryOf(id).region;
      if (land != null && land.contains(region)) return id;
    }
    return null;
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

/// The same for whether each layer is active, which the canvas asks for
/// every layer on every frame.
final _inactiveCache = Expando<Map<String, String?>>('inactive reasons');

String? _findProblem(GardenDocument document, String layerId) {
  if (!document.layers.containsKey(layerId)) return null;
  final layer = document.layers[layerId]!;
  final geometry = document.geometryOf(layerId);
  final ownProblem = geometryProblem(geometry);
  if (ownProblem != null) return ownProblem;

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

  final parentKind = layer.kind.parentKind;
  if (parentKind != null) {
    for (final id in ids) {
      if (_holderOf(document, parentKind, regions[id]!) == null) {
        return '${geometry.labelOf(id)} is not inside a '
            '${parentKind.label.toLowerCase()}';
      }
    }
    if (!_constructionInside(document, parentKind, geometry)) {
      return 'Drawing is not inside a ${parentKind.label.toLowerCase()}';
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

/// Whether unfinished drawing (lines and points not yet part of a closed
/// shape) lies inside land of [kind], so a stroke outside the field turns
/// red while it is drawn. Where there is no such land yet, nothing is out.
bool _constructionInside(
  GardenDocument document,
  LayerKind kind,
  Geometry geometry,
) {
  final holders = [
    for (final id in document.drawingOrder)
      if (document.layers[id]!.kind == kind) ?document.geometryOf(id).region,
  ];
  if (holders.isEmpty) return true;
  final closed = geometry.closedIds.toSet();
  final covered = geometry.definingPoints(closed);
  final coveredEdges = {
    for (final id in closed)
      for (final ring in geometry.shapes[id]?.rings ?? <List<SegmentRef>>[])
        for (final ref in ring) ref.segmentId,
  };
  for (final line in geometry.lines.values) {
    if (coveredEdges.contains(line.id)) continue;
    final edge = line.curve(geometry.points);
    if (!holders.any((land) => land.containsEdge(edge))) return false;
    covered.addAll([line.start, line.end]);
  }
  for (final entry in geometry.points.entries) {
    if (covered.contains(entry.key)) continue;
    if (!holders.any(
      (land) => land.locate(entry.value) != PointLocation.outside,
    )) {
      return false;
    }
  }
  return true;
}

String? _holderOf(GardenDocument document, LayerKind kind, Region region) {
  for (final id in document.drawingOrder) {
    if (document.layers[id]!.kind != kind) continue;
    final land = document.geometryOf(id).region;
    if (land != null && land.contains(region)) return id;
  }
  return null;
}
