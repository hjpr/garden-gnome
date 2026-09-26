import 'document.dart';
import 'layer.dart';

/// A layer's decorative pattern, kept in its Properties so the Pattern
/// tool and the Properties panel change the same value. One pattern covers
/// every shape on the layer. Patterns never affect area or land rules.
extension FillPatterns on GardenDocument {
  /// The pattern stored for [layerId], whether or not it is shown.
  FillPattern? storedPatternOf(String layerId) =>
      layers[layerId]?.properties.pattern;

  /// The pattern to draw: none until the layer has closed land.
  FillPattern? patternOf(String layerId) {
    if (!layers.containsKey(layerId) || !geometryOf(layerId).isClosed) {
      return null;
    }
    return storedPatternOf(layerId);
  }

  /// This document with [layerId]'s pattern set to [pattern] (null for
  /// none). Returns this same document when nothing would change.
  ///
  /// Throws [StateError] when the layer has no closed land to fill.
  GardenDocument withPattern(String layerId, FillPattern? pattern) {
    final layer = layers[layerId]!;
    if (storedPatternOf(layerId) == pattern) return this;
    if (!geometryOf(layerId).isClosed) {
      throw StateError('Draw a closed shape before adding a pattern');
    }
    return withLayer(
      layer.copyWith(properties: layer.properties.withPattern(pattern)),
    );
  }
}
