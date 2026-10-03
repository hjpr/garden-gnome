import 'climate.dart';
import 'planting.dart';
import 'variety.dart';

/// Everything the growing tools keep: the Seed Vault, every planting, and
/// the garden's climate. Immutable; each change makes a new record.
///
/// This is the gardener's, not a drawing's, so it stays the same when a
/// different drawing is opened in Plan.
class GardenRecord {
  GardenRecord({
    this.climate = const Climate(),
    Map<String, Variety> varieties = const {},
    Map<String, Planting> plantings = const {},
    this.counter = 0,
  }) : varieties = Map.unmodifiable(varieties),
       plantings = Map.unmodifiable(plantings);

  final Climate climate;
  final Map<String, Variety> varieties;
  final Map<String, Planting> plantings;

  /// Highest ID number issued, so IDs are never reused.
  final int counter;

  GardenRecord copyWith({
    Climate? climate,
    Map<String, Variety>? varieties,
    Map<String, Planting>? plantings,
    int? counter,
  }) => GardenRecord(
    climate: climate ?? this.climate,
    varieties: varieties ?? this.varieties,
    plantings: plantings ?? this.plantings,
    counter: counter ?? this.counter,
  );

  /// A fresh ID such as "variety-12", and the record that has issued it.
  (GardenRecord, String) nextId(String prefix) {
    final n = counter + 1;
    return (copyWith(counter: n), '$prefix-$n');
  }

  GardenRecord withVariety(Variety v) =>
      copyWith(varieties: {...varieties, v.id: v});

  /// Removes the variety and every planting of it.
  GardenRecord withoutVariety(String id) => copyWith(
    varieties: {...varieties}..remove(id),
    plantings: {
      for (final p in plantings.values)
        if (p.varietyId != id) p.id: p,
    },
  );

  GardenRecord withPlanting(Planting p) =>
      copyWith(plantings: {...plantings, p.id: p});

  GardenRecord withoutPlanting(String id) =>
      copyWith(plantings: {...plantings}..remove(id));
}
