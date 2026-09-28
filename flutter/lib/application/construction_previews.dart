part of 'previews.dart';

/// Three-click arc feedback. Before the third position exists, only the
/// construction guide is drawn; a valid third position previews the real arc.
/// Either function can leave [through] or [end] unknown until its click.
class ArcPreview extends Preview {
  const ArcPreview({
    required this.start,
    this.through,
    this.end,
    this.curve,
    required this.valid,
    this.joinTarget,
    super.guides,
  });

  final Vec start;
  final Vec? through;
  final Vec? end;
  final CurveEdge? curve;
  final bool valid;

  /// The existing point [end] would reuse, if any.
  final String? joinTarget;
}

/// The next piece of a Line → Curve drawing: from the last point ([from],
/// null before the first) to the pointer ([to]). [toHandle] and
/// [outHandle] are the handle tips being pulled out at [to]; they equal
/// [to] for a sharp corner.
class CurvePreview extends Preview {
  const CurvePreview({
    required this.from,
    required this.fromHandle,
    required this.to,
    required this.toHandle,
    required this.outHandle,
    required this.valid,
    this.joinTarget,
    super.guides,
  });

  final Vec? from;
  final Vec? fromHandle;
  final Vec to;
  final Vec toHandle;
  final Vec outHandle;
  final bool valid;

  /// The existing point [to] would join, if any.
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
