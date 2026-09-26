import 'package:garden_gnome/domain/geometry.dart';

/// Shorthands for tests that draw one shape per layer: the bottom shape of
/// the layer's stack.
extension FirstShape on Geometry {
  String? get boundaryId => stack.firstOrNull;
  ClosedShape? get boundary => shapes[boundaryId];
  Circle? get boundaryCircle => circles[boundaryId];
  List<String> get boundaryCorners =>
      boundaryId == null ? const [] : cornersOf(boundaryId!);
  List<String> get boundaryAnchors =>
      boundaryId == null ? const [] : definingPoints([boundaryId!]).toList();
}
