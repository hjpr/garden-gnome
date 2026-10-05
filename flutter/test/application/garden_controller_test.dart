import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/farm.dart';
import 'package:garden_gnome/application/garden_controller.dart';
import 'package:garden_gnome/application/toasts.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/grow/climate.dart';
import 'package:garden_gnome/domain/grow/crop.dart';
import 'package:garden_gnome/domain/grow/day.dart';
import 'package:garden_gnome/domain/grow/garden_record.dart';
import 'package:garden_gnome/domain/grow/planting.dart';
import 'package:garden_gnome/domain/grow/variety.dart';
import 'package:garden_gnome/persistence/crop_catalog_codec.dart';

import '../support/grow_fixtures.dart';
import '../support/memory_garden_record_store.dart';

GardenController _garden(MemoryGardenRecordStore store, DateTime today) =>
    GardenController(
      store: store,
      toasts: ToastCenter(),
      catalog: testCatalog,
      clock: () => today,
    );

void main() {
  test('old shared plantings and climate move into the open farm', () async {
    final saved = GardenRecord(
      climate: const Climate(zone: HardinessZone(5, 'b')),
      varieties: const {
        'variety-1': Variety(
          id: 'variety-1',
          cropId: 'tomatoes',
          name: 'Big Beef',
        ),
      },
      plantings: {
        'planting-2': Planting(
          id: 'planting-2',
          varietyId: 'variety-1',
          sownOn: DateTime.utc(2026, 3, 20),
          startedIndoors: true,
          count: 72,
        ),
      },
      counter: 2,
    );
    final store = MemoryGardenRecordStore(saved);
    final farm = _UnsavedFarm();
    final garden = GardenController(
      store: store,
      toasts: ToastCenter(),
      catalog: testCatalog,
      clock: () => DateTime(2026, 4, 1),
      farm: farm,
    );
    final catalog = Completer<CropCatalog>();
    final loading = garden.load(catalog: () => catalog.future);

    // The vault refuses changes until the record is read.
    garden.addVariety('lettuce', 'Early');
    await Future<void>.delayed(Duration.zero);
    expect(garden.loaded, isFalse);
    expect(store.saves, 0);
    expect(garden.toasts.toasts.last.message, contains('loading'));

    catalog.complete(testCatalog);
    await loading;
    expect(garden.record.varieties.keys, ['variety-1']);
    final moved = garden.plantings.values.single;
    expect(moved.id, 'planting-1', reason: 'numbered by the farm');
    expect(moved.count, 72);
    expect(garden.climate.zone.code, '5b');
    expect(farm.labels, ['Move plantings into this farm']);
    // Until the farm is saved, the record keeps its copy.
    expect((await store.load()).plantings, hasLength(1));

    farm.saved();
    await Future<void>.delayed(Duration.zero);
    final after = await store.load();
    expect(after.plantings, isEmpty);
    expect(after.climate, const Climate());
    expect(after.varieties.keys, ['variety-1']);
    expect(garden.plantings, hasLength(1));
  });

  test(
    'vault changes are refused before and during the initial record read',
    () async {
      final store = MemoryGardenRecordStore(GardenRecord(counter: 7));
      final storedText = store.storedText;
      final garden = _garden(store, DateTime(2026, 4, 1));
      addTearDown(garden.dispose);
      addTearDown(garden.toasts.dispose);

      garden.addVariety('lettuce', 'Early');
      expect(store.saves, 0);
      final loading = garden.load();
      expect(garden.loaded, isFalse);
      garden.addVariety('lettuce', 'Also early');
      await loading;

      expect(garden.loaded, isTrue);
      expect(garden.record.counter, 7);
      expect(garden.record.varieties, isEmpty);
      expect(store.storedText, storedText);
      expect(store.saves, 0);
    },
  );

  test(
    'sowing, planting out, finishing and climate belong to the farm',
    () async {
      final store = MemoryGardenRecordStore();
      final farm = DetachedFarm();
      final garden = GardenController(
        store: store,
        toasts: ToastCenter(),
        catalog: testCatalog,
        clock: () => DateTime(2026, 3, 20, 15, 30),
        farm: farm,
      );
      await garden.load();
      final id = garden.addVariety('tomatoes', ' Big Beef ');
      expect(garden.profileOf(id)!.displayName, 'Big Beef · Tomatoes');

      final p = garden.sow(id, indoors: true, count: 72);
      expect(farm.farm.plantings[p]!.count, 72);
      expect(garden.schedules(PlantingStage.greenhouse).single.planting.id, p);
      garden.plantOut(p, on: DateTime(2026, 5, 2));
      expect(garden.schedules(PlantingStage.greenhouse), isEmpty);
      expect(
        garden.schedules(PlantingStage.inGround).single.planting.count,
        72,
      );
      garden.setZone(const HardinessZone(5, 'b'));
      expect(farm.farm.climate.zone.code, '5b');

      await Future<void>.delayed(Duration.zero);
      final stored = await store.load();
      expect(stored.plantings, isEmpty, reason: 'not kept in the browser');
      expect(stored.climate, const Climate());

      final back = farm.farm.plantings[p]!;
      expect(back.sownOn, DateTime.utc(2026, 3, 20));
      expect(back.plantedOutOn, DateTime.utc(2026, 5, 2));
      garden.finish(p);
      expect(garden.schedules(PlantingStage.inGround), isEmpty);

      // Removing a variety hides its plantings; vault IDs are never reused.
      garden.removeVariety(id);
      expect(garden.schedules(PlantingStage.finished), isEmpty);
      expect(garden.addVariety('lettuce', ''), isNot(id));
    },
  );

  test('overrides typed on a variety are saved', () async {
    final store = MemoryGardenRecordStore();
    final garden = _garden(store, DateTime(2026, 4, 1));
    await garden.load();
    final id = garden.addVariety('lettuce', 'Salanova');
    garden.updateVariety(
      garden.record.varieties[id]!.copyWith(
        daysToMaturity: () => const IntRange(55, 55),
        sowing: () => SowingMethod.transplant,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final reopened = _garden(store, DateTime(2026, 4, 2));
    await reopened.load();
    expect(
      reopened.record.varieties[id]!.daysToMaturity,
      const IntRange(55, 55),
    );
    expect(reopened.record.varieties[id]!.sowing, SowingMethod.transplant);
  });

  test(
    'a record that cannot be read is kept, and changes are refused',
    () async {
      const stored = '{"version": 99, "kept": "for a newer build"}';
      final store = MemoryGardenRecordStore.holding(stored);
      final garden = _garden(store, DateTime(2026, 4, 1));
      await garden.load();
      expect(garden.loaded, isTrue);
      expect(garden.recordProblem, contains('newer'));
      garden.addVariety('lettuce', 'Lost');
      await Future<void>.delayed(Duration.zero);
      expect(garden.record.varieties, isEmpty);
      expect(store.saves, 0);
      expect(store.storedText, stored);
      expect(garden.toasts.toasts.last.message, contains('not being kept'));
    },
  );

  test('cover crops stay in the vault, off the calendars', () async {
    final garden = _garden(MemoryGardenRecordStore(), DateTime(2026, 4, 1));
    await garden.load();
    final rye = garden.addVariety('winter-rye', 'Winter Rye (Common)');
    final beef = garden.addVariety('tomatoes', 'Big Beef');
    expect(garden.profiles.map((p) => p.id), [beef]);
    expect(garden.profileOf(rye), isNull);
    expect(garden.coverVarieties.single.$1.id, rye);
    expect(garden.coverVarieties.single.$2.name, 'Winter Rye');
    expect(garden.recommendations().map((r) => r.profile.id).toSet(), {beef});
    final (added, skipped) = garden.importVarieties([
      const Variety(id: 'x', cropId: 'winter-rye', name: 'Winter Rye (Common)'),
      const Variety(id: 'y', cropId: 'winter-rye', name: 'Other Rye'),
    ]);
    expect((added, skipped), (1, 1));
  });

  test('reorder opens the catalog product page, or the own link', () async {
    final opened = <String>[];
    final garden = GardenController(
      store: MemoryGardenRecordStore(),
      toasts: ToastCenter(),
      catalog: testCatalog,
      clock: () => DateTime(2026, 4, 1),
      openLink: (url) async {
        opened.add(url);
        return true;
      },
    );
    await garden.load();
    // addVariety replaces the record, so read it after the call.
    Variety add(String name) {
      final id = garden.addVariety('tomatoes', name);
      return garden.record.varieties[id]!;
    }

    final beef = add('big beef');
    final own = add(
      'Sun Gold',
    ).copyWith(url: () => 'https://example.test/sun-gold');
    final unknown = add('Grandma');
    expect(garden.reorderUrlOf(beef), bigBeefUrl);
    expect(garden.reorderUrlOf(own), 'https://example.test/sun-gold');
    expect(garden.reorderUrlOf(unknown), isNull);
    await garden.reorder(beef);
    await garden.reorder(unknown);
    expect(opened, [bigBeefUrl]);
  });

  test('a link that cannot be opened says so', () async {
    final garden = GardenController(
      store: MemoryGardenRecordStore(),
      toasts: ToastCenter(),
      catalog: testCatalog,
      openLink: (_) async => false,
    );
    await garden.load();
    final id = garden.addVariety('tomatoes', 'Big Beef');
    await garden.reorder(garden.record.varieties[id]!);
    expect(garden.toasts.toasts.last.message, 'Could not open $bigBeefUrl');
  });

  test('the bundled catalog loads with every crop usable', () async {
    final text = File('assets/catalog/crops.json').readAsStringSync();
    final catalog = decodeCropCatalog(text);
    final raw = RegExp(r'"id":').allMatches(text).length;
    expect(catalog.crops.length, greaterThan(100));
    expect(catalog.crops.length, raw, reason: 'no crop was skipped');
    for (final crop in catalog.crops) {
      if (crop.sowing.canTransplant) {
        expect(crop.weeksToTransplant, isNotNull, reason: crop.name);
      }
    }
    expect(catalog['tomatoes']!.sections, isNotEmpty);
    // Something is always plantable at some point in a 6a year.
    final garden = GardenController(
      store: MemoryGardenRecordStore(),
      toasts: ToastCenter(),
      catalog: catalog,
      clock: () => DateTime(2026, 5, 1),
    );
    await garden.load();
    for (final crop in catalog.crops) {
      garden.addVariety(crop.id, crop.name);
    }
    expect(dayOf(garden.today), DateTime.utc(2026, 5, 1));
    expect(garden.recommendations().where((r) => r.timing.isOpen), isNotEmpty);
  });
}

/// A farm with unsaved changes until [saved] is called.
class _UnsavedFarm extends DetachedFarm {
  bool _unsaved = false;
  final labels = <String>[];

  @override
  bool get farmUnsaved => _unsaved;

  @override
  void changeFarm(
    String label,
    GardenDocument Function(GardenDocument farm) change,
  ) {
    labels.add(label);
    _unsaved = true;
    super.changeFarm(label, change);
  }

  void saved() {
    _unsaved = false;
    notifyListeners();
  }
}
