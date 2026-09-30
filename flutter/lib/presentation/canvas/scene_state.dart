import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../application/camera.dart';
import '../../application/previews.dart';
import '../../application/transform_box.dart';
import '../../application/workspace_settings.dart';
import '../../domain/document.dart';
import '../../domain/reference_image.dart';
import '../../domain/units.dart';
import '../../domain/vec.dart';
import 'render_assets.dart';

/// Everything the painter needs, gathered so painting never reads the
/// controller or changes state.
class SceneState {
  const SceneState({
    required this.document,
    required this.camera,
    required this.appearance,
    required this.selectedLayerId,
    required this.selection,
    required this.preview,
    required this.lineAnchor,
    this.units = Units.feet,
    this.referencePictures = const {},
    this.referenceOpacity,
    this.selectedImageId,
    this.referenceLineImageId,
    this.referenceLineStart,
    this.devicePixelRatio = 1,
    this.selectionBox,
    this.guideMarkers = const [],
    this.showCurveHandles = false,
    this.viewMode = ViewMode.wireframe,
    this.renderAssets,
    this.selectedFeatureId,
    this.viewMoving = false,
  });

  final GardenDocument document;
  final Camera camera;
  final Appearance appearance;
  final String? selectedLayerId;
  final Set<String> selection;
  final Preview? preview;
  final String? lineAnchor;

  /// How lengths such as a circle's diameter are labelled.
  final Units units;

  /// Decoded reference pictures by their bytes; null while loading.
  final Map<Uint8List, ui.Image?> referencePictures;

  /// Opacity to draw each reference image with (live while its slider
  /// moves), or null to use the saved values.
  final double Function(ReferenceImage image)? referenceOpacity;

  /// The reference image showing corner handles, if any.
  final String? selectedImageId;

  /// The image a reference line is being drawn on, and its first end in
  /// that image's pixels.
  final String? referenceLineImageId;
  final Vec? referenceLineStart;

  /// Physical pixels per logical pixel, so hatch tiles are drawn at the
  /// screen's own sharpness.
  final double devicePixelRatio;

  /// The dashed box with scale handles around the selected shapes, or
  /// null when there is none.
  final TransformBox? selectionBox;

  /// Where guides come from right now (the geometry last hovered), marked
  /// so the user can see what a move or new point will line up with.
  final List<Vec> guideMarkers;

  /// Whether the selected curves show their Bézier handles (Select, on an
  /// unlocked layer).
  final bool showCurveHandles;

  /// Wireframe for drawing, or the Render view of the farm.
  final ViewMode viewMode;

  /// Textures and feature pictures; null in tests that do not need them,
  /// which then see plain colours.
  final RenderAssets? renderAssets;

  /// The feature showing its selection ring, if any.
  final String? selectedFeatureId;

  /// Whether the view is panning or zooming right now. Render then skips
  /// the costly blended ground edges and draws them once it settles.
  final bool viewMoving;
}
