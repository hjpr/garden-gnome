import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/grow/climate.dart';
import '../domain/grow/crop.dart';
import '../domain/grow/day.dart';
import '../domain/grow/garden_record.dart';
import '../domain/grow/planting.dart';
import '../domain/grow/planting_windows.dart';
import '../domain/grow/variety.dart';
import '../domain/layer.dart';
import '../domain/plant_layout.dart';
import '../domain/zone_ground.dart';
import 'farm.dart';
import 'garden_record_store.dart';
import 'toasts.dart';

/// A planting layer on the map with a seed in it and nothing sown yet.
class PlannedSowing {
  const PlannedSowing({
    required this.layerId,
    required this.layerName,
    required this.profile,
    required this.plants,
  });

  final String layerId;
  final String layerName;
  final VarietyProfile profile;

  /// How many plants its layout fits, or null with no land to plant.
  final int? plants;
}

/// A Cover bed on the map with its cover crop in the ground.
class CoverBed {
  const CoverBed({
    required this.layerId,
    required this.layerName,
    required this.cover,
  });

  final String layerId;
  final String layerName;
  final CoverSowing cover;
}

/// Runs the Seed Vault and Grow (Sow and Transplant).
///
/// The Seed Vault is the gardener's, kept in this browser's record and
/// changed through [_change] (which saves it). Climate and plantings
/// belong to the open farm: they are read from [farm] and changed as
/// farm edits, saved when the farm is saved. Answers the questions the
/// screens ask: what to plant now, what is in the greenhouse, what is
/// coming ready to pick.
///
/// Vault changes are refused until the initial load finishes. A stored
/// record this build cannot read is left where it is: the vault opens
/// empty but refuses changes, so the record is never written over.
class GardenController extends ChangeNotifier {
  GardenController({
    required this.store,
    required this.toasts,
    CropCatalog? catalog,
    GardenRecord? record,
    DateTime Function()? clock,
    FarmAccess? farm,
    Future<bool> Function(String url)? openLink,
  }) : _catalog = catalog ?? CropCatalog.empty,
       _record = record ?? GardenRecord(),
       _clock = clock ?? DateTime.now,
       _openLink = openLink,
       farm = farm ?? DetachedFarm() {
    this.farm.addListener(_onFarmChanged);
  }

  final GardenRecordStore store;

  /// The open farm, whose climate and plantings the tools show.
  final FarmAccess farm;
  final ToastCenter toasts;
  final DateTime Function() _clock;

  /// Opens a web page outside the app (platform/open_link.dart, injected
  /// at startup). Null in tests, where nothing is opened.
  final Future<bool> Function(String url)? _openLink;

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
    _moveOldPlantingsIntoFarm();
    notifyListeners();
  }

  // --------------------------------------------- moving the old record

  /// The farm editor the old record's plantings were moved into this run,
  /// and the planting counter that holds them. Once that farm is saved,
  /// the old copies are cleared from the record.
  (Object, int)? _moved;
  bool _moveTried = false;

  /// Before farms held their own plantings and climate, they were kept in
  /// this browser's record. They move, once, into the farm open now, as
  /// one Undo step. The record keeps its copy until the farm is saved, so
  /// leaving without saving loses nothing: they move again next time.
  void _moveOldPlantingsIntoFarm() {
    if (_moveTried || _recordProblem != null) return;
    _moveTried = true;
    final old = _record.plantings.values.toList();
    final climate = _record.climate;
    final hasClimate = climate != const Climate();
    if (old.isEmpty && !hasClimate) return;
    farm.changeFarm('Move plantings into this farm', (f) {
      var next = f;
      if (hasClimate && f.climate == const Climate()) {
        next = next.withClimate(climate);
      }
      for (final p in old) {
        final (withId, id) = next.nextPlantingId();
        next = withId.withPlanting(p.withId(id));
      }
      return next;
    });
    _moved = (farm.farmIdentity, farm.farm.plantingCounter);
    if (old.isNotEmpty) {
      toasts.show(
        'Moved ${old.length} ${old.length == 1 ? 'planting' : 'plantings'} '
        'into ${farm.farmName}. Save it to keep them with this farm',
      );
    }
    _settleMovedPlantings();
  }

  void _settleMovedPlantings() {
    final (identity, counter) = _moved ?? (null, 0);
    if (identity == null ||
        !identical(identity, farm.farmIdentity) ||
        farm.farmUnsaved ||
        farm.farm.plantingCounter < counter) {
      return;
    }
    _moved = null;
    _change(_record.copyWith(plantings: const {}, climate: const Climate()));
  }

  void _onFarmChanged() {
    _settleMovedPlantings();
    notifyListeners();
  }

  @override
  void dispose() {
    farm.removeListener(_onFarmChanged);
    super.dispose();
  }

  /// Today, as a calendar day.
  DateTime get today => dayOf(_clock());

  /// The open farm's climate.
  Climate get climate => farm.farm.climate;

  /// The open farm's plantings, by ID.
  Map<String, Planting> get plantings => farm.farm.plantings;

  PlantingPlanner get planner => PlantingPlanner(climate);

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

  void _changeClimate(Climate next) {
    if (next == climate) return;
    farm.changeFarm('Change climate', (f) => f.withClimate(next));
  }

  void setZone(HardinessZone zone) =>
      _changeClimate(climate.copyWith(zone: zone));

  /// Sets the farm's latitude in degrees north; null clears it.
  void setLatitude(double? latitude) =>
      _changeClimate(climate.copyWith(latitude: () => latitude));

  /// Sets the farm's own frost dates; null goes back to the zone's.
  void setFrostDates({
    MonthDay? Function()? lastSpring,
    MonthDay? Function()? firstFall,
  }) => _changeClimate(
    climate.copyWith(lastSpringFrost: lastSpring, firstFallFrost: firstFall),
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

  /// Cover crop varieties in the vault, by name. They are kept out of
  /// [profiles], so the calendars and Plant never offer them.
  List<(Variety, CoverCrop)> get coverVarieties => [
    for (final v in _record.varieties.values)
      if (_catalog.coverCrop(v.cropId) case final cover?) (v, cover),
  ]..sort((a, b) => a.$1.name.compareTo(b.$1.name));

  /// Where to reorder [v]: its own link if it has one, else its product
  /// page in the catalog, or null when the catalog does not list it.
  String? reorderUrlOf(Variety v) =>
      v.url ?? _catalog.productUrlOf(v.cropId, v.name);

  /// Opens [v]'s product page to reorder it.
  Future<void> reorder(Variety v) async {
    final url = reorderUrlOf(v);
    if (url == null) return;
    final opened = await _openLink?.call(url) ?? false;
    if (!opened) {
      toasts.show('Could not open $url', kind: ToastKind.error);
    }
  }

  /// Adds a variety of [cropId] and returns its ID.
  String addVariety(String cropId, String name) {
    final (next, id) = _record.nextId('variety');
    final clean = name.trim().isEmpty
        ? (_catalog.nameOf(cropId) ?? 'New variety')
        : name.trim();
    _change(next.withVariety(Variety(id: id, cropId: cropId, name: clean)));
    return id;
  }

  /// Adds [incoming] varieties under new IDs, as one change. A variety
  /// already in the vault (same crop and name) or whose crop is not in the
  /// catalog is skipped. Returns how many were added and skipped.
  (int, int) importVarieties(List<Variety> incoming) {
    String key(Variety v) => '${v.cropId}|${v.name.trim().toLowerCase()}';
    final known = {for (final v in _record.varieties.values) key(v)};
    var next = _record;
    var added = 0;
    for (final v in incoming) {
      if (!_catalog.knows(v.cropId) || !known.add(key(v))) continue;
      final (withId, id) = next.nextId('variety');
      next = withId.withVariety(v.copyWith(id: id));
      added++;
    }
    if (added > 0) _change(next);
    return (added, incoming.length - added);
  }

  void updateVariety(Variety variety) {
    if (!_record.varieties.containsKey(variety.id)) return;
    _change(_record.withVariety(variety));
  }

  /// Removes the variety from the vault. Farm plantings of it stay in
  /// their farms but are no longer shown.
  void removeVariety(String id) {
    final name = _record.varieties[id]?.name;
    _change(_record.withoutVariety(id));
    if (name != null) toasts.show('Removed $name');
  }

  // ------------------------------------------------------------ plantings

  /// Records a sowing of [varietyId] on the open farm today, in the
  /// greenhouse or in place, as one Undo step.
  String sow(
    String varietyId, {
    required bool indoors,
    DateTime? on,
    int? count,
    String location = '',
  }) {
    final name = _record.varieties[varietyId]?.name ?? 'Planting';
    late String id;
    farm.changeFarm('Sow $name', (f) {
      final (next, newId) = f.nextPlantingId();
      id = newId;
      return next.withPlanting(
        Planting(
          id: id,
          varietyId: varietyId,
          sownOn: dayOf(on ?? today),
          startedIndoors: indoors,
          count: count,
          location: location,
        ),
      );
    });
    toasts.show(
      indoors ? '$name started in the greenhouse' : '$name sown',
      kind: ToastKind.success,
    );
    return id;
  }

  /// Starts [varietyId] in the greenhouse today in [containers] flats of
  /// [cellsPerFlat] cells, or pots of one plant each, as one Undo step.
  String startInGreenhouse(
    String varietyId, {
    required GrowContainer container,
    required int containers,
    int cellsPerFlat = 1,
    DateTime? on,
  }) {
    final name = _record.varieties[varietyId]?.name ?? 'Planting';
    late String id;
    farm.changeFarm('Start $name', (f) {
      final (next, newId) = f.nextPlantingId();
      id = newId;
      return next.withPlanting(
        Planting(
          id: id,
          varietyId: varietyId,
          sownOn: dayOf(on ?? today),
          startedIndoors: true,
          container: container,
          containers: containers < 1 ? 1 : containers,
          cellsPerFlat: cellsPerFlat < 1 ? 1 : cellsPerFlat,
        ),
      );
    });
    toasts.show('$name started in the greenhouse', kind: ToastKind.success);
    return id;
  }

  /// Moves a greenhouse planting into the ground.
  void plantOut(String plantingId, {DateTime? on, String? location}) {
    final p = plantings[plantingId];
    if (p == null || !p.isInGreenhouseOn(today)) return;
    _changePlanting(
      'Plant out',
      p.copyWith(plantedOutOn: () => dayOf(on ?? today), location: location),
    );
  }

  void _changePlanting(String label, Planting next) =>
      farm.changeFarm(label, (f) => f.withPlanting(next));

  /// Marks a planting as done: harvested or pulled.
  void finish(String plantingId, {DateTime? on}) {
    final p = plantings[plantingId];
    if (p == null) return;
    _changePlanting(
      'Finish planting',
      p.copyWith(finishedOn: () => dayOf(on ?? today)),
    );
  }

  void updatePlanting(Planting planting) {
    final current = plantings[planting.id];
    if (current == null || current == planting) return;
    _changePlanting('Change planting', planting);
  }

  void removePlanting(String id) {
    if (!plantings.containsKey(id)) return;
    farm.changeFarm('Remove planting', (f) => f.withoutPlanting(id));
  }

  /// Plantings at [stage] with their expected dates, oldest sowing first.
  /// Plantings whose variety has gone are left out.
  List<PlantingSchedule> schedules(PlantingStage stage) => [
    for (final p in plantings.values)
      if (p.stage == stage)
        if (profileOf(p.varietyId) case final profile?)
          PlantingSchedule(p, profile),
  ]..sort((a, b) => a.planting.sownOn.compareTo(b.planting.sownOn));

  /// Everything growing in the greenhouse today, ready or not, oldest
  /// sowing first: trays not yet planted out, and planting layers whose
  /// Transplanted date is still ahead.
  List<PlantingSchedule> inGreenhouse() => [
    for (final p in plantings.values)
      if (p.isInGreenhouseOn(today))
        if (profileOf(p.varietyId) case final profile?)
          PlantingSchedule(p, profile),
  ]..sort((a, b) => a.planting.sownOn.compareTo(b.planting.sownOn));

  /// Everything in the ground and not finished, oldest sowing first:
  /// sown in place, or planted out of the greenhouse.
  List<PlantingSchedule> inGround() => [
    for (final p in plantings.values)
      if (p.finishedOn == null && !p.isInGreenhouseOn(today))
        if (profileOf(p.varietyId) case final profile?)
          PlantingSchedule(p, profile),
  ]..sort((a, b) => a.planting.sownOn.compareTo(b.planting.sownOn));

  /// Planting layers ready to sow: a seed from the vault and nothing
  /// growing there yet. Only these can be sown from Grow, so planning on
  /// the map comes first.
  List<PlannedSowing> plannedSowings() {
    final document = farm.farm;
    return [
      for (final layer in document.layers.values)
        if (layer.properties case ZoneProperties(:final seed?, isGrow: true))
          if (document.currentPlantingOf(layer.id) == null)
            if (profileOf(seed.varietyId) case final profile?)
              PlannedSowing(
                layerId: layer.id,
                layerName: layer.name,
                profile: profile,
                plants: document.plantLayoutOf(layer.id)?.count,
              ),
    ]..sort((a, b) => a.layerName.compareTo(b.layerName));
  }

  /// Cover beds with a cover crop sown (or dated ahead) and not yet
  /// terminated, soonest sowing first. Cover crops have no planting
  /// windows, so they are only listed once the gardener dates them.
  List<CoverBed> coverBeds() {
    final document = farm.farm;
    return [
      for (final layer in document.layers.values)
        if (layer.properties case ZoneProperties(
          isCover: true,
          cover: final cover?,
        ) when cover.isGrowingOn(today))
          CoverBed(layerId: layer.id, layerName: layer.name, cover: cover),
    ]..sort((a, b) => a.cover.sownOn!.compareTo(b.cover.sownOn!));
  }

  /// Marks Cover bed [layerId]'s cover crop as terminated on [on] (today
  /// by default), as one Undo step.
  void terminateCover(String layerId, {DateTime? on}) {
    final layer = farm.farm.layers[layerId];
    final props = layer?.properties;
    if (props is! ZoneProperties || props.cover == null) return;
    final day = dayOf(on ?? today);
    final sown = props.cover!.sownOn;
    final next = props.cover!.copyWith(
      terminatedOn: () => sown != null && day.isBefore(sown) ? sown : day,
    );
    try {
      farm.changeFarm(
        'Terminate ${props.cover!.name}',
        (f) => f.withCover(layerId, next),
      );
    } on StateError catch (e) {
      toasts.show(e.message, kind: ToastKind.error);
    }
  }

  /// How many plants planting layer [layerId]'s layout fits, or null.
  int? plannedPlantsOf(String layerId) =>
      farm.farm.plantLayoutOf(layerId)?.count;

  /// Sows planting layer [layerId] on [on] (today by default), as one
  /// Undo step. The layer's seed sets the variety.
  void sowPlanting(String layerId, {DateTime? on}) {
    final name = farm.farm.layers[layerId]?.name ?? 'Planting';
    try {
      farm.changeFarm(
        'Sow $name',
        (f) => f.withSownOn(layerId, dayOf(on ?? today)),
      );
    } on StateError catch (e) {
      toasts.show(e.message, kind: ToastKind.error);
      return;
    }
    toasts.show('$name sown', kind: ToastKind.success);
  }

  /// The name of the planting layer [p] grows in, or null.
  String? layerNameOf(Planting p) => farm.farm.layers[p.layerId]?.name;

  /// What to sow or plant: windows open now or opening within a year.
  List<Recommendation> recommendations({
    Set<WindowKind> kinds = const {...WindowKind.values},
  }) => recommend(profiles, planner, today, kinds: kinds);
}
