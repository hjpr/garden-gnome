import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/grow/planting.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/zone_ground.dart';

import '../support/ground_fixtures.dart';

void main() {
  test('dates need a seed, and Sown comes before Transplanted', () {
    final (editor, _, soil, grow) = garden(GroundType.flat);
    editor.setSownOn(grow, DateTime.utc(2027, 3, 1));
    expect(editor.notice, 'Plant a seed here first');
    editor.setSownOn(soil, DateTime.utc(2027, 3, 1));
    expect(editor.notice, 'Dates are set on plantings');

    editor.setSeed(grow, seed());
    editor.setTransplantedOn(grow, DateTime.utc(2027, 4, 1));
    expect(editor.notice, 'Set the Sown date first');
    editor.setSownOn(grow, DateTime.utc(2027, 3, 1));
    editor.setTransplantedOn(grow, DateTime.utc(2027, 2, 1));
    expect(editor.notice, 'Transplanted must be on or after Sown');
    editor.setTransplantedOn(grow, DateTime.utc(2027, 4, 1));
    editor.setSownOn(grow, DateTime.utc(2027, 5, 1));
    expect(editor.notice, 'Sown must be on or before Transplanted');
    expect(editor.document.plantings, hasLength(1));
  });

  test('the sowing follows the seed and the layer', () {
    final (editor, _, _, grow) = garden(GroundType.flat);
    editor.setSeed(grow, seed());
    editor.setSownOn(grow, DateTime.utc(2027, 3, 1));
    const other = ZoneSeed(
      varietyId: 'variety-2',
      name: 'Other',
      inRow: 0.75,
      betweenRows: 0.75,
    );
    editor.setSeed(grow, other);
    expect(editor.document.currentPlantingOf(grow)!.varietyId, 'variety-2');

    editor.setSeed(grow, null);
    expect(editor.document.plantings, isEmpty, reason: 'no seed, no sowing');
    editor.undo();
    expect(editor.document.plantings, hasLength(1));

    editor.deleteLayer(grow);
    expect(editor.document.plantings, isEmpty);
  });

  test('a greenhouse sowing with a planned Transplanted date is still in '
      'the greenhouse until that day', () {
    final p = Planting(
      id: 'planting-1',
      varietyId: 'variety-1',
      sownOn: DateTime.utc(2026, 9, 20),
      startedIndoors: true,
      plantedOutOn: DateTime.utc(2026, 10, 20),
    );
    expect(p.isInGreenhouseOn(DateTime.utc(2026, 10, 3)), isTrue);
    expect(p.isInGreenhouseOn(DateTime.utc(2026, 10, 20)), isFalse);
    expect(
      p
          .copyWith(plantedOutOn: () => null)
          .isInGreenhouseOn(DateTime.utc(2027, 1, 1)),
      isTrue,
    );
    expect(
      p
          .copyWith(startedIndoors: false)
          .isInGreenhouseOn(DateTime.utc(2026, 10, 3)),
      isFalse,
    );
  });

  test('a greenhouse tray dropped on a planting is planned out there', () {
    final (editor, _, _, grow) = garden(GroundType.flat);
    final tray = Planting(
      id: 'planting-1',
      varietyId: 'variety-1',
      sownOn: DateTime.utc(2027, 3, 1),
      startedIndoors: true,
      container: GrowContainer.flat,
      containers: 2,
      cellsPerFlat: 50,
    );
    editor.commit('Start', editor.documentForEditing.withPlanting(tray));
    final out = DateTime.utc(2027, 4, 12);
    editor.placeTray(grow, tray.id, seed(), out);
    expect(editor.undoLabel, 'Plan Test · Crop out');
    final placed = editor.document.plantings[tray.id]!;
    expect(placed.layerId, grow);
    expect(placed.plantedOutOn, out);
    expect(placed.plants, 100);
    expect(editor.document.currentPlantingOf(grow)!.id, tray.id);
    expect(
      (editor.document.layers[grow]!.properties as ZoneProperties).seed,
      seed(),
    );

    // Taking the seed out sends the tray back to the greenhouse.
    editor.setSeed(grow, null);
    final back = editor.document.plantings[tray.id]!;
    expect(back.layerId, isNull);
    expect(back.plantedOutOn, isNull);
    expect(back.isInGreenhouseOn(DateTime.utc(2027, 3, 5)), isTrue);
    editor.undo();

    // Clearing Transplanted keeps it a greenhouse tray.
    editor.setTransplantedOn(grow, null);
    expect(editor.document.plantings[tray.id]!.startedIndoors, isTrue);
    editor.undo();

    // Deleting the planting layer keeps the tray too.
    editor.deleteLayer(grow);
    expect(editor.document.plantings[tray.id]!.layerId, isNull);
  });

  test('a tray replaces a sowing already in the planting', () {
    final (editor, _, _, grow) = garden(GroundType.flat);
    editor.setSeed(grow, seed());
    editor.setSownOn(grow, DateTime.utc(2027, 3, 1));
    final direct = editor.document.currentPlantingOf(grow)!;
    final tray = Planting(
      id: 'planting-9',
      varietyId: 'variety-2',
      sownOn: DateTime.utc(2027, 3, 1),
      startedIndoors: true,
      container: GrowContainer.pot,
      containers: 6,
    );
    editor.commit('Start', editor.documentForEditing.withPlanting(tray));
    const other = ZoneSeed(
      varietyId: 'variety-2',
      name: 'Other',
      inRow: 0.75,
      betweenRows: 0.75,
    );
    // Planned for before it was sown: goes out the day it was sown.
    editor.placeTray(grow, tray.id, other, DateTime.utc(2027, 2, 1));
    expect(editor.document.plantings.containsKey(direct.id), isFalse);
    expect(
      editor.document.plantings[tray.id]!.plantedOutOn,
      DateTime.utc(2027, 3, 1),
    );
  });
}
