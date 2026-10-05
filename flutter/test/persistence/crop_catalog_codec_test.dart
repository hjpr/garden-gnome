import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/persistence/crop_catalog_codec.dart';

void main() {
  test('catalog reads and sorts named varieties with their parent crops', () {
    final json =
        jsonDecode(File('assets/catalog/crops.json').readAsStringSync())
            as Map<String, dynamic>;
    json['varieties'] = [
      {
        'id': 'tomato-1',
        'cropId': 'tomatoes',
        'name': 'Sun Gold',
        'url': 'https://example.test/sun-gold',
      },
      {'id': 'lettuce-1', 'cropId': 'lettuce', 'name': 'Adriana'},
    ];

    final catalog = decodeCropCatalog(jsonEncode(json));
    final varieties = catalog.varieties;
    expect(varieties.map((v) => v.name), ['Adriana', 'Sun Gold']);
    expect(varieties.last.cropId, 'tomatoes');
    expect(varieties.last.url, 'https://example.test/sun-gold');
    expect(() => varieties.clear(), throwsUnsupportedError);
  });

  test('invalid and duplicate variety entries do not hide valid entries', () {
    final catalog = decodeCropCatalog(
      File('assets/catalog/crops.json').readAsStringSync(),
      varietiesText: jsonEncode({
        'varieties': [
          {'id': '1', 'cropId': 'tomatoes', 'name': 'Sun Gold'},
          {'id': '1', 'cropId': 'tomatoes', 'name': 'Duplicate'},
          {'id': '2', 'cropId': 'missing-crop', 'name': 'Unknown'},
          {'id': '3', 'cropId': 'tomatoes', 'name': '  '},
          {'id': '', 'cropId': 'tomatoes', 'name': 'Empty ID'},
          {'id': '4', 'cropId': 'tomatoes', 'name': 'Bad URL', 'url': 42},
          {'id': '5', 'cropId': 'lettuce', 'name': 'Adriana'},
          {'id': '6'},
          null,
        ],
      }),
    );
    expect(catalog.varieties.map((v) => v.name), ['Adriana', 'Sun Gold']);
  });

  test('bundled cover crops load with their varieties and product links', () {
    final catalog = decodeCropCatalog(
      File('assets/catalog/crops.json').readAsStringSync(),
      varietiesText: File('assets/catalog/varieties.json').readAsStringSync(),
      coverCropsText: File(
        'assets/catalog/cover_crops.json',
      ).readAsStringSync(),
    );
    final raw =
        jsonDecode(File('assets/catalog/cover_crops.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(catalog.coverCrops.length, (raw['crops'] as List).length);
    expect(catalog.coverCrops.length, greaterThanOrEqualTo(20));
    expect(catalog.categories.last, 'Cover crops');
    final rye = catalog.coverCrop('winter-rye')!;
    expect(rye.minGermTempF, 34);
    expect(rye.sections, isNotEmpty);
    // Cover crops are never planning crops.
    expect(catalog['winter-rye'], isNull);
    expect(catalog.knows('winter-rye'), isTrue);
    final coverVarieties = catalog.varieties.where(
      (v) => catalog.coverCrop(v.cropId) != null,
    );
    expect(coverVarieties.length, (raw['varieties'] as List).length);
    for (final v in catalog.varieties) {
      expect(v.url, startsWith('https://www.johnnyseeds.com/'), reason: v.name);
      expect(catalog.productUrlOf(v.cropId, v.name), v.url);
    }
    expect(
      catalog.productUrlOf('peas', ' sugar ann '),
      contains('sugar-ann-pea-seed-559'),
    );
  });

  test('unreadable cover crops are skipped and never shadow a crop', () {
    final cover = {
      'id': 'clover',
      'name': 'Clover',
      'sowingSeason': 'Spring',
      'minGermTempF': 41,
      'hardinessZone': '4',
      'growthRate': 'Fast',
      'seedPer1000SqFt': '½ Lb.',
      'seedPerAcre': '8 Lb.',
      'sowingDepth': '¼"',
    };
    final catalog = decodeCropCatalog(
      File('assets/catalog/crops.json').readAsStringSync(),
      coverCropsText: jsonEncode({
        'crops': [
          cover,
          {...cover, 'id': 'tomatoes'},
          {...cover, 'id': 'no-temp', 'minGermTempF': null},
        ],
        'varieties': [
          {'id': '1', 'cropId': 'clover', 'name': 'Red'},
          {'id': '2', 'cropId': 'no-temp', 'name': 'Lost'},
        ],
      }),
    );
    expect(catalog.coverCrops.map((c) => c.id), ['clover']);
    expect(catalog['tomatoes'], isNotNull);
    expect(catalog.varieties.map((v) => v.name), ['Red']);
  });
}
