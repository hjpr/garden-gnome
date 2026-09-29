part of 'canvas_input.dart';

/// Pointer input for features (raised beds, greenhouses, high tunnels).
/// They sit on top of the land: Select picks a feature before the inside
/// of a shape, but points and lines still win so outlines under a
/// feature stay editable. Dragging a feature moves it, snapping its
/// centre like a point.
extension _FeatureInput on CanvasInput {
  /// The topmost feature under [screen], or null.
  Feature? _featureUnder(Offset screen) {
    final world = editor.camera.toWorld(screen);
    for (final feature in editor.document.features.reversed) {
      if (feature.contains(world)) return feature;
    }
    return null;
  }

  /// The feature Select would pick at [screen]: one under the pointer,
  /// unless a point, line or circle edge is within reach there.
  Feature? _featureOnTop(Offset screen) {
    final feature = _featureUnder(screen);
    if (feature == null) return null;
    final top = _selectHits(screen).firstOrNull;
    if (top != null && top.kind != HitKind.interior) return null;
    return feature;
  }

  _FeatureDrag? _startFeatureDrag(_Press press) {
    if (editor.tool != Tool.select) return null;
    final feature = _featureOnTop(press.origin);
    if (feature == null) return null;
    editor.selectFeature(feature.id);
    return _FeatureDrag(
      original: feature,
      grabOffset: editor.camera.toWorld(press.origin) - feature.centre,
    );
  }

  void _updateFeatureDrag(_FeatureDrag drag, Offset screen) {
    // The centre snaps, not the pointer, so the feature lines up.
    final snap = _snappedWorld(
      editor.camera.toWorld(screen) - drag.grabOffset,
      exclude: const {},
    );
    drag.candidate = drag.original.copyWith(centre: snap.position);
    editor.setPreview(FeatureMovePreview(drag.candidate!, guides: snap.guides));
  }

  void _finishFeatureDrag(_FeatureDrag drag) {
    editor.setPreview(null);
    final candidate = drag.candidate;
    if (candidate == null || candidate.centre == drag.original.centre) return;
    editor.updateFeature('Move ${candidate.displayName}', candidate);
    editor.selectFeature(candidate.id);
  }

  /// Feature tool: the footprint the next click would place, under the
  /// pointer.
  FeatureMovePreview? _featurePlacePreview(Offset screen) {
    final kind = editor.function.featureKind;
    if (kind == null) return null;
    final snap = _snapped(screen);
    return FeatureMovePreview(
      Feature.placed('preview', kind, snap.position),
      placing: true,
      guides: snap.guides,
    );
  }
}

/// A Select drag on a feature.
class _FeatureDrag {
  _FeatureDrag({required this.original, required this.grabOffset});

  final Feature original;

  /// Where the pointer grabbed, relative to the centre.
  final Vec grabOffset;

  /// The feature as it would be if released now.
  Feature? candidate;
}
