part of 'canvas_input.dart';

/// Pointer input for features (raised beds, greenhouses, high tunnels).
/// Select picks one as described at [SelectionTargets];
/// dragging it moves it, snapping its centre like a point. The Feature
/// tool places one where it is clicked.
extension _FeatureInput on CanvasInput {
  _FeatureDrag _startFeatureDrag(_Press press, Feature feature) {
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

  /// Feature tool: a click places one at its usual size, centred on the
  /// pointer (snapped like a point). Features sit on top of the land, so
  /// no layer is needed.
  void _featureClick(Offset screen) {
    final kind = editor.function.featureKind;
    if (kind == null) return;
    editor.showNotice(null);
    editor.addFeature(kind, _snapped(screen).position);
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
