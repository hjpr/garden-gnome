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
  }) => Planting(
    id: id,
    varietyId: varietyId,
    sownOn: sownOn ?? this.sownOn,
    startedIndoors: startedIndoors,
    plantedOutOn: plantedOutOn == null ? this.plantedOutOn : plantedOutOn(),
    finishedOn: finishedOn == null ? this.finishedOn : finishedOn(),
    count: count == null ? this.count : count(),
    location: location ?? this.location,
    notes: notes ?? this.notes,
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
