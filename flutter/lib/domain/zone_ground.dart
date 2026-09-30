import 'document.dart';
import 'layer.dart';
import 'row_layout.dart';

/// A zone's ground, kept in its Properties so the Ground tool and the
/// Properties panel change the same value. One ground covers every shape
/// on the zone. Ground never changes area or land rules.
extension ZoneGround on GardenDocument {
  /// The zone's ground as stored, whether or not it has land yet; null
  /// for plain dirt or for a layer that is not a zone.
  GroundType? storedGroundOf(String layerId) =>
      switch (layers[layerId]?.properties) {
        ZoneProperties p => p.ground,
        _ => null,
      };

  /// The zone's row settings, or null for a layer that is not a zone.
  RowSpec? rowsOf(String layerId) => switch (layers[layerId]?.properties) {
    ZoneProperties p => p.rows,
    _ => null,
  };

  /// Where the zone's rows fall: each of its closed shapes laid out on
  /// its own. Null unless the zone has row ground and land.
  RowLayout? rowLayoutOf(String layerId) {
    final properties = layers[layerId]?.properties;
    if (properties is! ZoneProperties || properties.ground != GroundType.row) {
      return null;
    }
    final geometry = geometryOf(layerId);
    if (geometry.closedIds.isEmpty) return null;
    return RowLayout.ofPieces([
      for (final id in geometry.closedIds) geometry.regionOf(id)!,
    ], properties.rows);
  }

  /// This document with [layerId]'s ground set to [ground] (null for plain
  /// dirt). Returns this same document when nothing would change.
  ///
  /// Throws [StateError] when the layer is not a zone or has no closed
  /// land yet.
  GardenDocument withGround(String layerId, GroundType? ground) {
    final layer = layers[layerId]!;
    final properties = layer.properties;
    if (properties is! ZoneProperties) {
      throw StateError('Ground is set on zones. Add a zone first');
    }
    if (properties.ground == ground) return this;
    if (!geometryOf(layerId).isClosed) {
      throw StateError('Close a shape before setting its ground');
    }
    return withLayer(
      layer.copyWith(properties: properties.copyWith(ground: () => ground)),
    );
  }

  /// This document with [seed] planted in grow zone [layerId] (null takes
  /// the seed out). Returns this same document when nothing would change.
  ///
  /// Throws [StateError] when the layer is not a grow zone or the
  /// spacings cannot be used.
  GardenDocument withSeed(String layerId, ZoneSeed? seed) {
    final layer = layers[layerId]!;
    final properties = layer.properties;
    if (properties is! ZoneProperties || !properties.isGrow) {
      throw StateError('Seeds are planted in grow zones');
    }
    if (seed?.problem case final problem?) throw StateError(problem);
    if (properties.seed == seed) return this;
    return withLayer(
      layer.copyWith(properties: properties.copyWith(seed: () => seed)),
    );
  }

  /// This document with [layerId]'s row settings replaced. Returns this
  /// same document when nothing would change.
  ///
  /// Throws [StateError] when the layer is not a zone or the settings
  /// cannot be used.
  GardenDocument withRows(String layerId, RowSpec rows) {
    final layer = layers[layerId]!;
    final properties = layer.properties;
    if (properties is! ZoneProperties) {
      throw StateError('Rows are set on zones');
    }
    if (rows.problem case final problem?) throw StateError(problem);
    if (properties.rows == rows) return this;
    return withLayer(
      layer.copyWith(properties: properties.copyWith(rows: rows)),
    );
  }
}
