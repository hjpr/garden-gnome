import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/grow/climate.dart';
import '../domain/grow/crop.dart';
import '../domain/grow/day.dart';
import '../domain/grow/garden_record.dart';
import '../domain/grow/planting.dart';
import '../domain/grow/planting_windows.dart';
import '../domain/grow/variety.dart';
import 'garden_record_store.dart';
import 'toasts.dart';

/// Runs the Seed Vault, Grow, Greenhouse and Harvest tools.
///
/// Holds the crop catalog and the gardener's record, sends every change
/// through [_change] (which saves it), and answers the questions the
/// screens ask: what to plant now, what is in the greenhouse, what is
/// coming ready to pick.
///
/// Changes are refused until the initial load finishes. A stored record
/// this build cannot read is left where it is: the tools
/// open empty but refuse changes, so the record is never written over.
class GardenController extends ChangeNotifier {
  GardenController({
    required this.store,
    required this.toasts,
    CropCatalog? catalog,
    GardenRecord? record,
    DateTime Function()? clock,
  }) : _catalog = catalog ?? CropCatalog.empty,
       _record = record ?? GardenRecord(),
       _clock = clock ?? DateTime.now;

  final GardenRecordStore store;
  final ToastCenter toasts;
  final DateTime Function() _clock;

  CropCatalog _catalog;
  CropCatalog get catalog => _catalog;

  GardenRecord _record;
  GardenRecord get record => _record;

  bool _loaded = false;
  bool get loaded => _loaded;

  /// Why the stored record could not be read, or null when it was (or
  /// there was none). While set, every change is refused so the stored
  /// record survives until a build that can read it.
  String? get recordProblem => _recordProblem;
  String? _recordProblem;

  /// Reads the stored record and the catalog. A catalog that cannot be
  /// read leaves an empty one, so the tools still open.
  Future<void> load({Future<CropCatalog> Function()? catalog}) async {
    try {
      if (catalog != null) _catalog = await catalog();
    } catch (_) {
      toasts.show('Could not load the crop catalog', kind: ToastKind.error);
    }
    try {
      _record = await store.load();
      _recordProblem = null;
    } catch (e) {
      _recordProblem = '$e';
      toasts.show('$e. Changes are not being kept', kind: ToastKind.error);
    }
    _loaded = true;
    notifyListeners();
  }

  /// Today, as a calendar day.
  DateTime get today => dayOf(_clock());

  PlantingPlanner get planner => PlantingPlanner(_record.climate);

  void _change(GardenRecord next) {
    if (!_loaded) {
      toasts.show('Garden is still loading. Try again when it finishes');
      return;
    }
    if (_recordProblem case final problem?) {
      toasts.show(
        '$problem. Changes are not being kept',
        kind: ToastKind.error,
      );
      return;
    }
    _record = next;
    notifyListeners();
    unawaited(_save(next));
  }

  Future<void> _save(GardenRecord snapshot) async {
    try {
      await store.save(snapshot);
    } catch (e) {
      toasts.show('$e', kind: ToastKind.error);
    }
  }

  // ------------------------------------------------------------- climate

  void setZone(HardinessZone zone) =>
      _change(_record.copyWith(climate: _record.climate.copyWith(zone: zone)));

  /// Sets the gardener's own frost dates; null goes back to the zone's.
  void setFrostDates({
    MonthDay? Function()? lastSpring,
    MonthDay? Function()? firstFall,
  }) => _change(
    _record.copyWith(
      climate: _record.climate.copyWith(
        lastSpringFrost: lastSpring,
        firstFallFrost: firstFall,
      ),
    ),
  );

  // ---------------------------------------------------------- seed vault

  /// Varieties whose crop is in the catalog, with their planning values.
  List<VarietyProfile> get profiles => [
    for (final v in _record.varieties.values)
      if (_catalog[v.cropId] case final crop?) v.resolve(crop),
  ]..sort((a, b) => a.displayName.compareTo(b.displayName));

  VarietyProfile? profileOf(String varietyId) {
    final v = _record.varieties[varietyId];
    final crop = v == null ? null : _catalog[v.cropId];
    return crop == null ? null : v!.resolve(crop);
  }

  /// Adds a variety of [cropId] and returns its ID.
  String addVariety(String cropId, String name) {
    final (next, id) = _record.nextId('variety');
    final clean = name.trim().isEmpty
        ? (_catalog[cropId]?.name ?? 'New variety')
        : name.trim();
    _change(next.withVariety(Variety(id: id, cropId: cropId, name: clean)));
    return id;
  }

  void updateVariety(Variety variety) {
    if (!_record.varieties.containsKey(variety.id)) return;
    _change(_record.withVariety(variety));
  }

  /// Removes the variety and its plantings.
  void removeVariety(String id) {
    final name = _record.varieties[id]?.name;
    _change(_record.withoutVariety(id));
    if (name != null) toasts.show('Removed $name');
  }

  // ------------------------------------------------------------ plantings

  /// Records a sowing of [varietyId] today, in the greenhouse or in place.
  String sow(
    String varietyId, {
    required bool indoors,
    DateTime? on,
    int? count,
    String location = '',
  }) {
    final (next, id) = _record.nextId('planting');
    _change(
      next.withPlanting(
        Planting(
          id: id,
          varietyId: varietyId,
          sownOn: dayOf(on ?? today),
          startedIndoors: indoors,
          count: count,
          location: location,
        ),
      ),
    );
    final name = _record.varieties[varietyId]?.name ?? 'Planting';
    toasts.show(
      indoors ? '$name started in the greenhouse' : '$name sown',
      kind: ToastKind.success,
    );
    return id;
  }

  /// Moves a greenhouse planting into the ground.
  void plantOut(String plantingId, {DateTime? on, String? location}) {
    final p = _record.plantings[plantingId];
    if (p == null || p.stage != PlantingStage.greenhouse) return;
    _change(
      _record.withPlanting(
        p.copyWith(plantedOutOn: () => dayOf(on ?? today), location: location),
      ),
    );
  }

  /// Marks a planting as done: harvested or pulled.
  void finish(String plantingId, {DateTime? on}) {
    final p = _record.plantings[plantingId];
    if (p == null) return;
    _change(
      _record.withPlanting(p.copyWith(finishedOn: () => dayOf(on ?? today))),
    );
  }

  void updatePlanting(Planting planting) {
    if (!_record.plantings.containsKey(planting.id)) return;
    _change(_record.withPlanting(planting));
  }

  void removePlanting(String id) => _change(_record.withoutPlanting(id));

  /// Plantings at [stage] with their expected dates, oldest sowing first.
  /// Plantings whose variety has gone are left out.
  List<PlantingSchedule> schedules(PlantingStage stage) => [
    for (final p in _record.plantings.values)
      if (p.stage == stage)
        if (profileOf(p.varietyId) case final profile?)
          PlantingSchedule(p, profile),
  ]..sort((a, b) => a.planting.sownOn.compareTo(b.planting.sownOn));

  /// What to sow or plant within two months either side of today.
  List<Recommendation> recommendations({
    Set<WindowKind> kinds = const {...WindowKind.values},
  }) => recommend(profiles, planner, today, kinds: kinds);
}
