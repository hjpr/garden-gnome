import 'day.dart';
import 'variety.dart';

/// Where a planting is in its life.
enum PlantingStage {
  /// Sown in trays in the greenhouse, waiting to be planted out.
  greenhouse('In greenhouse'),

  /// Growing where it will be harvested.
  inGround('In ground'),

  /// Harvest finished or the planting was pulled.
  finished('Finished');

  const PlantingStage(this.label);

  final String label;
}

/// What greenhouse seed is started in. A flat holds several cells, one
/// plant each; a pot holds one plant.
enum GrowContainer {
  flat('Flat'),
  pot('Pot');

  const GrowContainer(this.label);

  final String label;
}

/// One sowing of one variety, followed from seed to harvest.
///
/// Sown in the greenhouse it appears in Greenhouse until it is planted
/// out; sown directly it goes straight to the ground. Once in the ground
/// it appears in Harvest.
class Planting {
  const Planting({
    required this.id,
    required this.varietyId,
    required this.sownOn,
    required this.startedIndoors,
    this.plantedOutOn,
    this.finishedOn,
    this.count,
    this.location = '',
    this.notes = '',
    this.layerId,
    this.container,
    this.containers = 1,
    this.cellsPerFlat = 1,
  });

  final String id;
  final String varietyId;
  final DateTime sownOn;

  /// Sown in the greenhouse to be transplanted, rather than in place.
  final bool startedIndoors;

  /// When transplants went into the ground; null while in the greenhouse
  /// and for direct sowings.
  final DateTime? plantedOutOn;
  final DateTime? finishedOn;

  /// Cells, plants or row feet, as the gardener counts them.
  final int? count;

  /// Where it is growing, in the gardener's words.
  final String location;
  final String notes;

  /// The planting layer it grows in on the farm map; null for a tray
  /// not yet in the ground, or a sowing made without the map.
  final String? layerId;

  /// For a greenhouse sowing, what it is started in; null otherwise.
  final GrowContainer? container;

  /// How many flats or pots.
  final int containers;

  /// Cells in each flat; a pot always holds one plant.
  final int cellsPerFlat;

  /// Plants available to plant out: cells across every flat, or one per
  /// pot. Falls back to [count] for sowings recorded without a container.
  int? get plants => switch (container) {
    GrowContainer.flat => containers * cellsPerFlat,
    GrowContainer.pot => containers,
    null => count,
  };

  PlantingStage get stage {
    if (finishedOn != null) return PlantingStage.finished;
    if (startedIndoors && plantedOutOn == null) return PlantingStage.greenhouse;
    return PlantingStage.inGround;
  }

  /// When it went into the ground: planted out, or sown in place.
  DateTime? get inGroundOn => startedIndoors ? plantedOutOn : sownOn;

  Planting copyWith({
    DateTime? sownOn,
    DateTime? Function()? plantedOutOn,
    DateTime? Function()? finishedOn,
    int? Function()? count,
    String? location,
    String? notes,
    String? varietyId,
    bool? startedIndoors,
    String? Function()? layerId,
    GrowContainer? Function()? container,
    int? containers,
    int? cellsPerFlat,
  }) => Planting(
    id: id,
    varietyId: varietyId ?? this.varietyId,
    sownOn: sownOn ?? this.sownOn,
    startedIndoors: startedIndoors ?? this.startedIndoors,
    plantedOutOn: plantedOutOn == null ? this.plantedOutOn : plantedOutOn(),
    finishedOn: finishedOn == null ? this.finishedOn : finishedOn(),
    count: count == null ? this.count : count(),
    location: location ?? this.location,
    notes: notes ?? this.notes,
    layerId: layerId == null ? this.layerId : layerId(),
    container: container == null ? this.container : container(),
    containers: containers ?? this.containers,
    cellsPerFlat: cellsPerFlat ?? this.cellsPerFlat,
  );

  /// A copy under another ID, e.g. when moved into a farm.
  Planting withId(String newId) => Planting(
    id: newId,
    varietyId: varietyId,
    sownOn: sownOn,
    startedIndoors: startedIndoors,
    plantedOutOn: plantedOutOn,
    finishedOn: finishedOn,
    count: count,
    location: location,
    notes: notes,
    layerId: layerId,
    container: container,
    containers: containers,
    cellsPerFlat: cellsPerFlat,
  );

  @override
  bool operator ==(Object other) =>
      other is Planting &&
      other.id == id &&
      other.varietyId == varietyId &&
      other.sownOn == sownOn &&
      other.startedIndoors == startedIndoors &&
      other.plantedOutOn == plantedOutOn &&
      other.finishedOn == finishedOn &&
      other.count == count &&
      other.location == location &&
      other.notes == notes &&
      other.layerId == layerId &&
      other.container == container &&
      other.containers == containers &&
      other.cellsPerFlat == cellsPerFlat;

  @override
  int get hashCode => Object.hash(
    id,
    varietyId,
    sownOn,
    startedIndoors,
    plantedOutOn,
    finishedOn,
    count,
    location,
    notes,
    layerId,
    container,
    containers,
    cellsPerFlat,
  );
}

/// A planting's expected dates, worked out from its variety.
class PlantingSchedule {
  PlantingSchedule(this.planting, this.profile);

  final Planting planting;
  final VarietyProfile profile;

  /// When seedlings should be up, or null when germination time is
  /// unknown.
  DayWindow? get germination {
    final g = profile.germinationDays;
    if (g == null) return null;
    return DayWindow(
      addDays(planting.sownOn, g.min),
      addDays(planting.sownOn, g.max),
    );
  }

  /// When greenhouse transplants are ready to plant out.
  DayWindow get plantOut {
    final w = profile.weeksToTransplant;
    return DayWindow(
      addDays(planting.sownOn, w.min * 7),
      addDays(planting.sownOn, w.max * 7),
    );
  }

  /// When the first harvest is expected, and how long picking lasts.
  DayWindow get harvest {
    final DateTime first;
    final out = planting.plantedOutOn;
    if (planting.startedIndoors) {
      // Not planted out yet: assume it goes out on the typical day.
      final planted =
          out ?? addDays(planting.sownOn, profile.weeksToTransplant.mid * 7);
      first = addDays(planted, profile.daysFromTransplant);
    } else {
      first = addDays(planting.sownOn, profile.daysFromDirectSowing);
    }
    return DayWindow(first, addDays(first, profile.harvestWindowDays.mid));
  }
}
