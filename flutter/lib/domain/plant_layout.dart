import 'dart:math' as math;

import 'document.dart';
import 'layer.dart';
import 'region.dart';
import 'row_layout.dart';
import 'vec.dart';
import 'zone_ground.dart';

/// Where the plants of a grow zone go, worked out from the ground under
/// it.
///
/// A grow zone is not soil: it marks what is planted on the Flat and Row
/// zones it is drawn over, and follows their rules.
///
/// - Over Row ground, plants go only along the rows. A bed wide enough for
///   more than one line at the seed's [ZoneSeed.betweenRows] gets several
///   lines, centred on the row.
/// - Over Flat ground, plants go on a grid: lines [ZoneSeed.betweenRows]
///   apart, running the Flat zone's direction.
/// - Along every line, plants are [ZoneSeed.inRow] apart.
/// - Over plain dirt, or outside any zone, nothing is planted.
/// - Where soil zones overlap, the topmost soil in drawing order wins,
///   including its paths and borders. Holes expose the soil below.
///
/// Plants keep half their [ZoneSeed.footprint] clear of line ends and
/// bed edges, and are centred on what they fill.
class PlantLayout {
  PlantLayout._(
    this.seed,
    this.lines,
    this.positions,
    this.count,
    this.lineLength,
    this.soils,
  );

  /// Positions kept for drawing. Beyond this the count is still exact but
  /// no more positions are stored: dense crops such as carrots on a big
  /// field would otherwise ask for millions.
  static const maxPositions = 50000;

  /// Most lines of plants on one row, however narrow the seed's spacing.
  static const maxLinesPerRow = 12;

  /// Most grid lines across flat ground in one grow zone.
  static const maxGridLines = 4000;

  final ZoneSeed seed;

  /// The lines plants are set along, clipped to the grow zone and the
  /// ground under it. Drawn instead of single plants when zoomed out.
  final List<RowRun> lines;

  /// Plant positions in world metres, up to [maxPositions].
  final List<Vec> positions;

  /// How many plants fit.
  final int count;

  /// Total length of the lines of plants, in metres.
  final double lineLength;

  /// The kinds of soil under the grow zone that were planted.
  final Set<GroundType> soils;
}

/// Plant layouts for grow zones.
extension ZonePlanting on GardenDocument {
  /// Where [layerId]'s plants go, or null unless it is a grow zone with a
  /// seed and land. Worked out once per document and zone.
  PlantLayout? plantLayoutOf(String layerId) {
    final cache = _plantLayouts[this] ??= {};
    if (cache.containsKey(layerId)) return cache[layerId];
    return cache[layerId] = _layout(layerId);
  }

  /// The Flat and Row zones a grow zone can plant on: the other zones of
  /// its property that have soil ground and land.
  List<String> soilZonesFor(String layerId) {
    final parent = parentOf(layerId);
    if (parent == null) return const [];
    return [
      for (final id in parent.children)
        if (id != layerId)
          if (layers[id]?.properties case ZoneProperties(
            :final ground?,
          ) when ground.isSoil && geometryOf(id).isClosed)
            id,
    ];
  }

  /// Most lines of [seed] that fit along the row beds under planting
  /// [layerId] at its between-row spacing: the widest bed's count, capped at
  /// [PlantLayout.maxLinesPerRow]. Null when no row bed lies under it.
  int? maxLinesOf(String layerId, ZoneSeed seed) {
    final grow = layers.containsKey(layerId)
        ? geometryOf(layerId).region
        : null;
    if (grow == null || seed.problem != null) return null;
    int? most;
    for (final soilId in soilZonesFor(layerId)) {
      final layout = rowLayoutOf(soilId);
      final region = geometryOf(soilId).region;
      if (layout == null || region == null || !region.overlaps(grow)) {
        continue;
      }
      final fit = math.min(
        PlantLayout.maxLinesPerRow,
        _fitting(layout.spec.width, seed, seed.betweenRows),
      );
      if (most == null || fit > most) most = fit;
    }
    return most;
  }

  PlantLayout? _layout(String layerId) {
    final properties = layers[layerId]?.properties;
    if (properties is! ZoneProperties || !properties.isGrow) return null;
    final seed = properties.seed;
    final growRegion = geometryOf(layerId).region;
    if (seed == null || seed.problem != null || growRegion == null) {
      return null;
    }
    final lines = <RowRun>[];
    final soils = <GroundType>{};
    final covered = <Region>[];
    // Sibling creation order is drawingOrder: visit the topmost soil first.
    for (final soilId in soilZonesFor(layerId).reversed) {
      final soil = layers[soilId]!.properties as ZoneProperties;
      final region = geometryOf(soilId).region!;
      var exposed = region;
      for (final higher in covered) {
        if (exposed.overlaps(higher)) {
          exposed = exposed.combine(higher, BooleanOperation.subtract);
        }
        if (exposed.contours.isEmpty) break;
      }
      // Claim the soil even when none of its beds can fit this seed.
      covered.add(region);
      if (exposed.contours.isEmpty) continue;
      final found = switch (soil.ground!) {
        GroundType.row => _rowLines(soilId, exposed, growRegion, seed),
        GroundType.flat => _gridLines(
          exposed,
          growRegion,
          seed,
          soil.rows.direction,
        ),
        GroundType.cover || GroundType.grow => const <RowRun>[],
      };
      if (found.isNotEmpty) soils.add(soil.ground!);
      lines.addAll(found);
    }
    return _plantAlong(lines, seed, soils);
  }

  /// Keep the original row alignment, clipping shifted plant lines to the
  /// exposed [soil] as well as the grow zone.
  List<RowRun> _rowLines(
    String soilId,
    Region soil,
    Region grow,
    ZoneSeed seed,
  ) {
    final layout = rowLayoutOf(soilId);
    if (layout == null) return const [];
    final (ax, ay) = layout.spec.along;
    final across = Vec(-ay, ax);
    // The seed's Lines setting caps it, but never past what fits.
    final perRow = math.min(
      math.min(PlantLayout.maxLinesPerRow, seed.lines ?? 1 << 30),
      _fitting(layout.spec.width, seed, seed.betweenRows),
    );
    final lines = <RowRun>[];
    for (final run in layout.runs) {
      for (var k = 0; k < perRow; k++) {
        final shift = across * ((k - (perRow - 1) / 2) * seed.betweenRows);
        for (final shifted in clipToRegion(
          grow,
          run.start + shift,
          run.end + shift,
        )) {
          lines.addAll(clipToRegion(soil, shifted.start, shifted.end));
        }
      }
    }
    return lines;
  }

  /// Grid lines across flat [soil] inside the grow zone, running
  /// [direction] degrees clockwise from north.
  List<RowRun> _gridLines(
    Region soil,
    Region grow,
    ZoneSeed seed,
    double direction,
  ) {
    final radians = direction * math.pi / 180;
    final along = Vec(math.sin(radians), -math.cos(radians));
    final across = Vec(-along.y, along.x);
    final (lowAcross, highAcross) = extentAlong(grow, across);
    final (lowAlong, highAlong) = extentAlong(grow, along);
    final span = highAcross - lowAcross;
    if (!(span > 0)) return const [];
    final count = _fitting(span, seed, seed.betweenRows);
    if (count > PlantLayout.maxGridLines) return const [];
    final lines = <RowRun>[];
    // Centre the lines, keeping half a footprint clear at each side.
    final first = lowAcross + (span - (count - 1) * seed.betweenRows) / 2;
    for (var i = 0; i < count; i++) {
      final offset = first + i * seed.betweenRows;
      final from = across * offset + along * (lowAlong - 1);
      final to = across * offset + along * (highAlong + 1);
      for (final run in clipToRegion(grow, from, to)) {
        lines.addAll(clipToRegion(soil, run.start, run.end));
      }
    }
    return lines;
  }
}

/// Places plants [ZoneSeed.inRow] apart along each line, centred on it.
PlantLayout _plantAlong(
  List<RowRun> lines,
  ZoneSeed seed,
  Set<GroundType> soils,
) {
  final positions = <Vec>[];
  var count = 0;
  var length = 0.0;
  for (final line in lines) {
    final runLength = line.length;
    length += runLength;
    final n = _fitting(runLength, seed, seed.inRow);
    if (n == 0) continue;
    count += n;
    if (positions.length >= PlantLayout.maxPositions) continue;
    final step = (line.end - line.start) / runLength * seed.inRow;
    final start =
        line.start +
        (line.end - line.start) /
            runLength *
            ((runLength - (n - 1) * seed.inRow) / 2);
    for (var i = 0; i < n && positions.length < PlantLayout.maxPositions; i++) {
      positions.add(start + step * i.toDouble());
    }
  }
  return PlantLayout._(
    seed,
    List.unmodifiable(lines),
    List.unmodifiable(positions),
    count,
    length,
    Set.unmodifiable(soils),
  );
}

/// How many plants or lines [pitch] apart fit in [length]: n of them
/// take one footprint plus (n - 1) pitches.
int _fitting(double length, ZoneSeed seed, double pitch) {
  final room = seed.footprint;
  if (length < room - 1e-9) return 0;
  return math.max(0, ((length - room) / pitch + 1e-9).floor() + 1);
}

final _plantLayouts = Expando<Map<String, PlantLayout?>>('plant layouts');
