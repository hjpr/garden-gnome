import '../domain/document.dart';

/// The points of every shape of [layerId]'s own zones that lies wholly
/// inside [shapeId], by zone. Moving or turning a whole property shape
/// carries these along. Zones carry nothing, so moving one zone never
/// drags another that it overlaps.
Map<String, Set<String>> landInside(
  GardenDocument document,
  String layerId,
  String shapeId,
) {
  final outer = document.geometryOf(layerId).regionOf(shapeId);
  if (outer == null) return const {};
  final result = <String, Set<String>>{};
  for (final other in document.layers[layerId]!.children) {
    final inner = document.geometryOf(other);
    final points = <String>{};
    for (final id in inner.closedIds) {
      if (outer.contains(inner.regionOf(id)!)) {
        points.addAll(inner.definingPoints([id]));
      }
    }
    if (points.isNotEmpty) result[other] = points;
  }
  return result;
}
