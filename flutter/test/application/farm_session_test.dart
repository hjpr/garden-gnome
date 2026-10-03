import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/document_session.dart';
import 'package:garden_gnome/application/farm.dart';
import 'package:garden_gnome/application/garden_controller.dart';
import 'package:garden_gnome/domain/grow/climate.dart';
import 'package:garden_gnome/domain/grow/day.dart';
import 'package:garden_gnome/domain/grow/planting.dart';
import 'package:garden_gnome/persistence/document_codec.dart';
import 'package:garden_gnome/persistence/drawing_library.dart';
import 'package:garden_gnome/persistence/workspace_store.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/grow_fixtures.dart';
import '../support/memory_garden_record_store.dart';

void main() {
  late DocumentSession session;
  late SessionFarm farm;
  late GardenController garden;
  late BrowserDrawingLibrary library;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    library = BrowserDrawingLibrary(factory: newIdbFactoryMemory());
    session = DocumentSession(
      library: library,
      workspace: WorkspaceStore(),
      codec: const GgnomeCodec(),
      lastFarm: LastFarmPreference(),
    );
    farm = SessionFarm(session);
    garden = GardenController(
      store: MemoryGardenRecordStore(),
      toasts: session.toasts,
      catalog: testCatalog,
      clock: () => DateTime(2026, 4, 1),
      farm: farm,
    );
    await garden.load();
  });

  test('plantings and climate are part of the open farm', () async {
    final tomato = garden.addVariety('tomatoes', 'Big Beef');
    garden.sow(tomato, indoors: true);
    garden.setZone(const HardinessZone(5, 'b'));
    expect(session.editor.document.plantings, hasLength(1));
    expect(session.hasUnsavedWork, isTrue, reason: 'a farm edit');
    expect(session.editor.undoLabel, 'Change climate');

    session.editor.undo();
    expect(garden.climate, const Climate());
    session.editor.undo();
    expect(garden.schedules(PlantingStage.greenhouse), isEmpty);
    session.editor.redo();
    session.editor.redo();

    expect(await session.saveAs('Home farm'), isA<Succeeded>());
    final entry = (await library.list()).single;

    await session.newDrawing();
    expect(garden.schedules(PlantingStage.greenhouse), isEmpty);
    expect(garden.climate, const Climate());
    expect(garden.record.varieties, hasLength(1), reason: 'vault is shared');

    await session.open(entry);
    expect(garden.schedules(PlantingStage.greenhouse), hasLength(1));
    expect(garden.climate.zone.code, '5b');
    expect(farm.farmName, 'Home farm');
  });

  test('the last farm saved or opened reopens at start-up', () async {
    garden.setZone(const HardinessZone(7, 'a'));
    await session.saveAs('Hill farm');

    final next = DocumentSession(
      library: library,
      workspace: WorkspaceStore(),
      codec: const GgnomeCodec(),
      lastFarm: LastFarmPreference(),
    );
    await next.reopenLastFarm();
    expect(next.editor.title, 'Hill farm');
    expect(next.editor.document.climate.zone.code, '7a');

    await next.newDrawing();
    final third = DocumentSession(
      library: library,
      workspace: WorkspaceStore(),
      codec: const GgnomeCodec(),
      lastFarm: LastFarmPreference(),
    );
    await third.reopenLastFarm();
    expect(third.editor.title, 'Untitled', reason: 'New was the last farm');
  });

  test('a farm file keeps its plantings and climate', () {
    final tomato = garden.addVariety('tomatoes', 'Big Beef');
    garden.sow(tomato, indoors: false, count: 12);
    garden.setFrostDates(lastSpring: () => const MonthDay(4, 20));
    final reopened = decodeGgnome(encodeGgnome(session.editor.document));
    expect(reopened.plantings.values.single.count, 12);
    expect(reopened.plantingCounter, 1);
    expect(reopened.climate.lastSpringFrost, const MonthDay(4, 20));
  });
}
