import 'dart:ui';

import '../domain/document.dart';
import '../domain/feature.dart';
import '../domain/reference_image.dart';
import 'camera.dart';
import 'hit_testing.dart';

const double referenceHandleReach = 10;

sealed class SelectionTarget {
  const SelectionTarget();
}

class ImageHandleTarget extends SelectionTarget {
  const ImageHandleTarget(this.image, this.corner);

  final ReferenceImage image;
  final int corner;
}

class LandTarget extends SelectionTarget {
  const LandTarget(this.hit);

  final LayerHit hit;
}

class FeatureTarget extends SelectionTarget {
  const FeatureTarget(this.feature);

  final Feature feature;
}

class ImageTarget extends SelectionTarget {
  const ImageTarget(this.image);

  final ReferenceImage image;
}

/// Resolves Select hover, click and drag against the same scene snapshot.
class SelectionTargets {
  const SelectionTargets({
    required this.document,
    required this.camera,
    required this.isFrozen,
    required this.overlaysEnabled,
    this.imagesEnabled = true,
    this.selectedImage,
  });

  final GardenDocument document;
  final Camera camera;
  final bool Function(String layerId) isFrozen;
  final bool overlaysEnabled;

  /// False while the Reference layer is hidden: its images cannot be
  /// picked.
  final bool imagesEnabled;
  final ReferenceImage? selectedImage;

  List<LayerHit> landAt(Offset screen) => [
    for (final hit in hitsAcrossLayers(document, camera, screen))
      if (!isFrozen(hit.layerId)) hit,
  ];

  SelectionTarget? at(Offset screen, {bool landOnly = false}) {
    final overlays = overlaysEnabled && !landOnly;
    final image = selectedImage;
    if (overlays && imagesEnabled && image != null && !image.locked) {
      for (final (corner, world) in image.corners.indexed) {
        if ((camera.toScreen(world) - screen).distance <=
            referenceHandleReach) {
          return ImageHandleTarget(image, corner);
        }
      }
    }
    final land = landAt(screen).firstOrNull;
    if (land != null && land.kind != HitKind.interior) return LandTarget(land);
    final world = camera.toWorld(screen);
    // Features cover land interiors, but leave outlines editable underneath.
    if (overlays) {
      for (final feature in document.features.reversed) {
        if (feature.contains(world)) return FeatureTarget(feature);
      }
    }
    if (land != null) return LandTarget(land);
    if (overlays && imagesEnabled) {
      for (final image in document.references.reversed) {
        if (!image.locked && image.containsWorld(world)) {
          return ImageTarget(image);
        }
      }
    }
    return null;
  }
}
