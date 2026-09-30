import '../domain/vec.dart';
import 'history.dart';

/// Unfinished tool input, separate from saved geometry and history snapshots.
class ConstructionState {
  int _nextToken = 0;
  int? lineToken;
  String? lineAnchor;
  Vec curveHandle = Vec.zero;
  final List<ArcPoint> arcPoints = [];
  CircleStart? circleStart;
  Vec? polygonStart;
  String? referenceImageId;
  Vec? referenceStart;

  bool get hasPendingClicks =>
      arcPoints.isNotEmpty ||
      circleStart != null ||
      polygonStart != null ||
      referenceStart != null;

  bool get isActive =>
      hasPendingClicks || lineAnchor != null || lineToken != null;

  int startLine() => lineToken = ++_nextToken;

  void reset() {
    lineToken = null;
    lineAnchor = null;
    curveHandle = Vec.zero;
    arcPoints.clear();
    circleStart = null;
    polygonStart = null;
    referenceImageId = null;
    referenceStart = null;
  }

  void restoreLine(
    LineContext? context,
    String? anchor, {
    required bool drawingLine,
  }) {
    final live =
        context != null && context.operation == lineToken && drawingLine;
    reset();
    if (live) {
      lineToken = context.operation;
      lineAnchor = anchor;
    }
    // Handles are not kept in history; the next piece starts straight.
  }
}

class ArcPoint {
  const ArcPoint(this.position, {this.pointId});

  final Vec position;
  final String? pointId;
}

class CircleStart {
  const CircleStart(this.position, {this.pointId});

  final Vec position;
  final String? pointId;
}
