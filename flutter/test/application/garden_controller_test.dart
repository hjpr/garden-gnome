import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/garden_controller.dart';
import 'package:garden_gnome/application/toasts.dart';
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
  test('early climate edits cannot overwrite the stored garden', () async {
    final saved = GardenRecord(
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
    final storedText = store.storedText;
    final garden = _garden(store, DateTime(2026, 4, 1));
    addTearDown(garden.dispose);
    addTearDown(garden.toasts.dispose);
    final catalog = Completer<CropCatalog>();
    final loading = garden.load(catalog: () => catalog.future);

    garden.setZone(const HardinessZone(5, 'b'));
    await Future<void>.delayed(Duration.zero);
    expect(garden.loaded, isFalse);
    expect(store.storedText, storedText);
    expect(store.saves, 0);
    expect(garden.record.climate.zone, saved.climate.zone);
    expect(garden.toasts.toasts.last.message, contains('loading'));

    catalog.complete(testCatalog);
    await loading;
    expect(garden.loaded, isTrue);
    expect(garden.record.varieties['variety-1']!.name, 'Big Beef');
    expect(garden.record.plantings['planting-2']!.count, 72);
    expect(garden.record.counter, 2);
    expect(store.saves, 0);

    garden.setZone(const HardinessZone(5, 'b'));
    await Future<void>.delayed(Duration.zero);
    final persisted = await store.load();
    expect(store.saves, 1);
    expect(persisted.climate.zone.code, '5b');
    expect(persisted.varieties['variety-1']!.name, 'Big Beef');
    expect(persisted.plantings['planting-2']!.count, 72);
    expect(persisted.counter, 2);
  });

  test(
    'changes are refused before and during the initial record read',
    () async {
      final store = MemoryGardenRecordStore(GardenRecord(counter: 7));
      final storedText = store.storedText;
      final garden = _garden(store, DateTime(2026, 4, 1));
      addTearDown(garden.dispose);
      addTearDown(garden.toasts.dispose);

      garden.setZone(const HardinessZone(5, 'b'));
      expect(store.saves, 0);
      final loading = garden.load();
      expect(garden.loaded, isFalse);
      garden.setFrostDates(lastSpring: () => const MonthDay(4, 20));
      await loading;

      expect(garden.loaded, isTrue);
      expect(garden.record.counter, 7);
      expect(garden.record.climate.lastSpringFrost, isNull);
      expect(store.storedText, storedText);
      expect(store.saves, 0);
    },
  );

  test('vault, sowing, planting out and finishing are saved', () async {
    final store = MemoryGardenRecordStore();
    final garden = _garden(store, DateTime(2026, 3, 20, 15, 30));
    await garden.load();
    final id = garden.addVariety('tomatoes', ' Big Beef ');
    expect(garden.profileOf(id)!.displayName, 'Big Beef · Tomatoes');

    final p = garden.sow(id, indoors: true, count: 72);
    expect(garden.schedules(PlantingStage.greenhouse).single.planting.id, p);
    garden.plantOut(p, on: DateTime(2026, 5, 2));
    expect(garden.schedules(PlantingStage.greenhouse), isEmpty);
    expect(garden.schedules(PlantingStage.inGround).single.planting.count, 72);

    garden.setZone(const HardinessZone(5, 'b'));
    await Future<void>.delayed(Duration.zero);
    final reopened = _garden(store, DateTime(2026, 5, 3));
    await reopened.load();
    expect(reopened.record.climate.zone.code, '5b');
    final back = reopened.record.plantings[p]!;
    expect(back.sownOn, DateTime.utc(2026, 3, 20));
    expect(back.plantedOutOn, DateTime.utc(2026, 5, 2));

    reopened.finish(p);
    expect(reopened.schedules(PlantingStage.inGround), isEmpty);
    // Ids are never reused, even after removal.
    reopened.removeVariety(id);
    expect(reopened.record.plantings, isEmpty);
    expect(reopened.addVariety('lettuce', ''), isNot(id));
  });

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
      garden.setZone(const HardinessZone(5, 'b'));
      await Future<void>.delayed(Duration.zero);
      expect(garden.record.varieties, isEmpty);
      expect(store.saves, 0);
      expect(store.storedText, stored);
      expect(garden.toasts.toasts.last.message, contains('not being kept'));
    },
  );

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
