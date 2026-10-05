import 'document.dart';
import 'grow/day.dart';
import 'grow/planting.dart';
import 'layer.dart';
import 'plant_layout.dart';
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
    if (properties is! ZoneProperties || properties.isGrow) {
      throw StateError('Ground is set on beds. Select a bed');
    }
    if (ground == GroundType.grow) {
      throw StateError('Add a planting in Layers to plant here');
    }
    if (properties.ground == ground) return this;
    if (!geometryOf(layerId).isClosed) {
      throw StateError('Close a shape before setting its ground');
    }
    return withLayer(
      layer.copyWith(properties: properties.copyWith(ground: () => ground)),
    );
  }

  /// This document with [cover] sown across Cover bed [layerId] (null
  /// takes it out). Choosing a different cover crop keeps the dates.
  /// Returns this same document when nothing would change.
  ///
  /// Throws [StateError] when the layer is not a Cover bed or the dates
  /// run backwards.
  GardenDocument withCover(String layerId, CoverSowing? cover) {
    final layer = layers[layerId];
    final properties = layer?.properties;
    if (properties is! ZoneProperties || !properties.isCover) {
      throw StateError(coverBedsOnly);
    }
    if (cover case CoverSowing(
      :final sownOn?,
      :final terminatedOn?,
    ) when terminatedOn.isBefore(sownOn)) {
      throw StateError('Terminated cannot be before Sown');
    }
    if (properties.cover == cover) return this;
    return withLayer(
      layer!.copyWith(properties: properties.copyWith(cover: () => cover)),
    );
  }

  /// Why a seed cannot go on a Cover bed or on plantings over one.
  static const coverBedsOnly = 'Cover crops are sown on Cover beds';

  /// The Cover beds of [layerId]'s property under planting [layerId];
  /// a planting over one cannot be seeded.
  bool isOverCover(String layerId) {
    final grow = layers.containsKey(layerId)
        ? geometryOf(layerId).region
        : null;
    final parent = parentOf(layerId);
    if (grow == null || parent == null) return false;
    for (final id in parent.children) {
      if (id == layerId) continue;
      if (layers[id]?.properties case ZoneProperties(isCover: true)) {
        final region = geometryOf(id).region;
        if (region != null && region.overlaps(grow)) return true;
      }
    }
    return false;
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
      throw StateError('Seeds are planted in plantings');
    }
    if (seed?.problem case final problem?) throw StateError(problem);
    // Lines never exceed what fits at this size and spacing; a wider
    // spacing brings them down with it.
    if (seed?.lines case final lines?) {
      final most = maxLinesOf(layerId, seed!);
      if (most != null && lines > most) {
        seed = seed.copyWith(lines: () => most < 1 ? null : most);
      }
    }
    if (properties.seed == seed) return this;
    var next = withLayer(
      layer.copyWith(properties: properties.copyWith(seed: () => seed)),
    );
    // The sowing follows the seed: another variety changes it, no seed
    // takes it out.
    if (currentPlantingOf(layerId) case final sowing?) {
      next = seed == null
          ? next.withoutSowing(sowing)
          : next.withPlanting(sowing.copyWith(varietyId: seed.varietyId));
    }
    return next;
  }

  /// [sowing] taken off the map: a greenhouse flat or pot goes back to
  /// the greenhouse unplanned; any other sowing is removed.
  GardenDocument withoutSowing(Planting sowing) => sowing.container == null
      ? withoutPlanting(sowing.id)
      : withPlanting(
          sowing.copyWith(layerId: () => null, plantedOutOn: () => null),
        );

  /// The sowing growing in planting layer [layerId] now: the latest one
  /// linked to it that is not finished. Null before a Sown date is set.
  Planting? currentPlantingOf(String layerId) {
    Planting? best;
    for (final p in plantings.values) {
      if (p.layerId != layerId || p.finishedOn != null) continue;
      if (best == null || p.sownOn.isAfter(best.sownOn)) best = p;
    }
    return best;
  }

  /// Sets when the seed in planting layer [layerId] was (or will be)
  /// sown, creating its sowing if there is none. Sown in place unless a
  /// Transplanted date is set.
  GardenDocument withSownOn(String layerId, DateTime day) {
    final seed = _plantingSeed(layerId);
    final sown = dayOf(day);
    if (currentPlantingOf(layerId) case final p?) {
      final transplanted = p.plantedOutOn;
      if (transplanted != null && transplanted.isBefore(sown)) {
        throw StateError('Sown must be on or before Transplanted');
      }
      return p.sownOn == sown ? this : withPlanting(p.copyWith(sownOn: sown));
    }
    final (next, id) = nextPlantingId();
    return next.withPlanting(
      Planting(
        id: id,
        varietyId: seed.varietyId,
        sownOn: sown,
        startedIndoors: false,
        layerId: layerId,
      ),
    );
  }

  /// Plans greenhouse tray [plantingId] to go out into planting layer
  /// [layerId] on [outOn]: the layer takes [seed] and the tray becomes
  /// its sowing, with [outOn] as its Transplanted date. Any other sowing
  /// still growing there is taken out, as when its seed is removed; a
  /// tray planned for another layer moves here.
  GardenDocument withTrayIn(
    String layerId,
    String plantingId,
    ZoneSeed seed,
    DateTime outOn,
  ) {
    final layer = layers[layerId];
    final properties = layer?.properties;
    if (properties is! ZoneProperties || !properties.isGrow) {
      throw StateError('Greenhouse plants go into plantings');
    }
    final tray = plantings[plantingId];
    if (tray == null || !tray.startedIndoors || tray.finishedOn != null) {
      throw StateError('That greenhouse sowing is gone');
    }
    if (seed.problem case final problem?) throw StateError(problem);
    final out = dayOf(outOn).isBefore(tray.sownOn) ? tray.sownOn : outOn;
    var next = properties.seed == seed
        ? this
        : withLayer(
            layer!.copyWith(properties: properties.copyWith(seed: () => seed)),
          );
    for (final p in plantings.values) {
      if (p.id != plantingId && p.layerId == layerId && p.finishedOn == null) {
        next = next.withoutSowing(p);
      }
    }
    final placed = tray.copyWith(
      varietyId: seed.varietyId,
      layerId: () => layerId,
      plantedOutOn: () => dayOf(out),
    );
    return placed == tray && identical(next, this)
        ? this
        : next.withPlanting(placed);
  }

  /// Sets when the seedlings in planting layer [layerId] went into the
  /// ground; null makes it sown in place again. Needs a Sown date first.
  GardenDocument withTransplantedOn(String layerId, DateTime? day) {
    _plantingSeed(layerId);
    final p = currentPlantingOf(layerId);
    if (p == null) throw StateError('Set the Sown date first');
    final out = day == null ? null : dayOf(day);
    if (out != null && out.isBefore(p.sownOn)) {
      throw StateError('Transplanted must be on or after Sown');
    }
    // A greenhouse flat or pot stays started indoors with no date: it is
    // simply not planned out yet.
    final indoors = out != null || p.container != null;
    if (p.plantedOutOn == out && p.startedIndoors == indoors) return this;
    return withPlanting(
      p.copyWith(plantedOutOn: () => out, startedIndoors: indoors),
    );
  }

  ZoneSeed _plantingSeed(String layerId) {
    final properties = layers[layerId]?.properties;
    if (properties is! ZoneProperties || !properties.isGrow) {
      throw StateError('Dates are set on plantings');
    }
    return properties.seed ?? (throw StateError('Plant a seed here first'));
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
