import '../domain/curve_edge.dart';
import '../domain/document.dart';
import '../domain/feature.dart';
import '../domain/reference_image.dart';
import '../domain/vec.dart';
import 'snapping.dart';
import 'transform_box.dart';

part 'construction_previews.dart';

/// Temporary feedback drawn over the canvas while a tool is in use.
///
/// Previews are never saved or undone. The painter only reads them.
sealed class Preview {
  const Preview({this.guides = SnapGuides.none});

  /// The dashed guides a snap lined the pointer up with, if any.
  final SnapGuides guides;

  String? get problem => null;
}

/// Where a new point would go. [lineId] is set when it would split a line.
class PointPreview extends Preview {
  const PointPreview(
    this.position, {
    required this.valid,
    this.lineId,
    super.guides,
  });

  final Vec position;
  final bool valid;
  final String? lineId;
}

/// The dashed line from the current anchor to the pointer.
///
/// [joinTarget] is the existing point that would be reused, if any.
class SegmentPreview extends Preview {
  const SegmentPreview(
    this.from,
    this.to, {
    required this.valid,
    this.joinTarget,
    super.guides,
  });

  final Vec from;
  final Vec to;
  final bool valid;
  final String? joinTarget;
}

/// A drag in progress: the drawing as it would be if released now.
class MovePreview extends Preview {
  const MovePreview({
    required this.document,
    required this.moved,
    required this.valid,
    this.box,
    super.guides,
  });

  /// The selection box turned with a rotation in progress; null for other
  /// drags, whose box is measured around the moved shapes.
  final TransformBox? box;

  final GardenDocument document;

  /// Points being moved in each layer; lines touching them are drawn dotted.
  final Map<String, Set<String>> moved;

  /// False when releasing here would leave a moved layer invalid.
  final bool valid;
}

/// An Align button's preview: the drawing with the second selected item
/// moved into line, drawn like a drag in progress. Its own kind, so
/// leaving the button clears only an Align preview.
class AlignPreview extends MovePreview {
  const AlignPreview({
    required super.document,
    required super.moved,
    required super.valid,
    this.problem,
  });

  @override
  final String? problem;
}

/// A circle being drawn, from its first click to the pointer.
///
/// A thin line joins the first click ([start]) to the pointer ([edge]):
/// the radius of a centre circle, or the width of a 2-point circle.
class CirclePreview extends Preview {
  const CirclePreview({
    required this.start,
    required this.edge,
    required this.centre,
    required this.radius,
    required this.valid,
    super.guides,
  });

  final Vec start;
  final Vec edge;
  final Vec centre;
  final double radius;
  final bool valid;
}

/// An existing item under the pointer that a click would act on.
///
/// [layerId] names the item's layer when it may not be the selected one,
/// as with the Select tool. [joinable] marks a point that a Line click
/// would reuse.
class HoverPreview extends Preview {
  const HoverPreview(
    this.itemId, {
    this.layerId,
    this.destructive = false,
    this.joinable = false,
  });

  final String itemId;
  final String? layerId;
  final bool destructive;
  final bool joinable;

  // Equal hovers compare equal, so moving within one item does not redraw.
  @override
  bool operator ==(Object other) =>
      other is HoverPreview &&
      other.itemId == itemId &&
      other.layerId == layerId &&
      other.destructive == destructive &&
      other.joinable == joinable;

  @override
  int get hashCode => Object.hash(itemId, layerId, destructive, joinable);
}

/// A seed being dragged over the canvas: [layerId] is the grow zone it
/// would be planted in, or null when letting go would plant nothing.
class SeedDropPreview extends Preview {
  const SeedDropPreview(this.layerId);

  final String? layerId;

  @override
  bool operator ==(Object other) =>
      other is SeedDropPreview && other.layerId == layerId;

  @override
  int get hashCode => layerId.hashCode;
}

/// A marquee or lasso being drawn with Select, in world metres, and what
/// letting go would select: [items] on [layerId] (null when nothing).
class AreaSelectPreview extends Preview {
  const AreaSelectPreview(
    this.outline, {
    required this.lasso,
    required this.layerId,
    required this.items,
  });

  final List<Vec> outline;
  final bool lasso;
  final String? layerId;
  final Set<String> items;
}

/// The reference image as it would be if a move or scale were released
/// now, drawn in place of the saved one.
class ReferencePreview extends Preview {
  const ReferencePreview(this.image);

  final ReferenceImage image;
}

/// A reference line being drawn, from its first click to the pointer, in
/// world metres. [valid] is false while the pointer is off the image.
class ReferenceLinePreview extends Preview {
  const ReferenceLinePreview(this.from, this.to, {required this.valid});

  final Vec from;
  final Vec to;
  final bool valid;
}

/// A feature under the Select pointer that a click would pick.
class FeatureHoverPreview extends Preview {
  const FeatureHoverPreview(this.featureId);

  final String featureId;

  @override
  bool operator ==(Object other) =>
      other is FeatureHoverPreview && other.featureId == featureId;

  @override
  int get hashCode => featureId.hashCode;
}

/// A feature being dragged, drawn where it would land, or ([placing]) the
/// footprint the Feature tool's next click would place.
class FeatureMovePreview extends Preview {
  const FeatureMovePreview(this.feature, {this.placing = false, super.guides});

  final Feature feature;
  final bool placing;
}
