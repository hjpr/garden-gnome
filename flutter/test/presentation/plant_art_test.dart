import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/presentation/canvas/plant_art.dart';

void main() {
  test('every mapped crop is in the catalog and its picture is bundled', () {
    final catalog =
        jsonDecode(File('assets/catalog/crops.json').readAsStringSync())
            as Map<String, Object?>;
    final ids = {
      for (final crop in catalog['crops']! as List)
        (crop as Map<String, Object?>)['id'],
    };
    for (final id in PlantArt.cropIds) {
      expect(ids, contains(id), reason: '$id is not a catalog crop');
      final kind = PlantArt.kindOf(id)!;
      expect(
        File('assets/render/plants/${kind}_1.png').existsSync(),
        isTrue,
        reason: '$kind has no picture',
      );
    }
    expect(PlantArt.kindOf('no-such-crop'), isNull);
    expect(PlantArt.kindOf(null), isNull);
  });

  test('every pictured crop has a canopy that fills its catalog spacing', () {
    final catalog =
        jsonDecode(File('assets/catalog/crops.json').readAsStringSync())
            as Map<String, Object?>;
    for (final raw in catalog['crops']! as List) {
      final crop = raw as Map<String, Object?>;
      final id = crop['id']! as String;
      final canopy = PlantArt.canopyOf(id);
      if (PlantArt.kindOf(id) == null) {
        expect(canopy, isNull);
        continue;
      }
      final inches = canopy! / 0.0254;
      final inRow = (crop['inRowSpacingIn']! as List).first as num;
      final between = (crop['betweenRowSpacingIn']! as List).first as num;
      // Neighbours in a line touch or overlap, and a plant never spans
      // more than about two lines' spacing.
      expect(inches, greaterThanOrEqualTo(inRow - 1e-9), reason: id);
      expect(inches, lessThanOrEqualTo(2 * between), reason: id);
    }
    expect(PlantArt.canopyOf(null), isNull);
    expect(PlantArt.canopyOf('no-such-crop'), isNull);
  });
}
