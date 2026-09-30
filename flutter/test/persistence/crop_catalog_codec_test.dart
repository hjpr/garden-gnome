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
}
