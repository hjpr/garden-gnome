import 'package:flutter_test/flutter_test.dart';
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
      size: 0.5,
      spacing: 0.25,
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
}
