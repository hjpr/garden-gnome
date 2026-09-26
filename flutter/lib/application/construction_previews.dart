part of 'previews.dart';

/// Three-click arc feedback. Before the third position exists, only the
/// construction guide is drawn; a valid third position previews the real arc.
class ArcPreview extends Preview {
  const ArcPreview({
    required this.start,
    required this.through,
    this.end,
    this.curve,
    required this.valid,
    this.joinTarget,
    super.guides,
  });

  final Vec start;
  final Vec through;
  final Vec? end;
  final CurveEdge? curve;
  final bool valid;
  final String? joinTarget;
}

/// A Polygon being drawn: its first click and the corners it would have
/// if the next click landed at the pointer. [corners] is empty while the
/// pointer is too close to the first click to make a shape.
class PolygonPreview extends Preview {
  const PolygonPreview({
    required this.start,
    required this.corners,
    required this.valid,
    super.guides,
  });

  final Vec start;
  final List<Vec> corners;
  final bool valid;
}

/// The whole document after a proposed Boolean edit. A refused operation
/// keeps the original scene and marks the operand red instead of inventing
/// a result that could not be committed.
class BooleanPreview extends Preview {
  const BooleanPreview({
    required this.layerId,
    required this.operandId,
    required this.valid,
    this.document,
    this.resultIds = const [],
    this.problem,
  });

  final String layerId;
  final String operandId;
  final bool valid;
  final GardenDocument? document;

  /// The shapes the operation would leave, bottom first.
  final List<String> resultIds;
  final String? problem;
}
