import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/persistence/crop_catalog_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled loader joins variety names to crop defaults', () async {
    final assets = {
      'assets/catalog/crops.json': File(
        'assets/catalog/crops.json',
      ).readAsStringSync(),
      'assets/catalog/varieties.json': jsonEncode({
        'varieties': [
          {'id': '1', 'cropId': 'tomatoes', 'name': 'Sun Gold'},
        ],
      }),
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    rootBundle.clear();
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      final text = assets[key];
      return text == null
          ? null
          : ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
    });
    addTearDown(() {
      messenger.setMockMessageHandler('flutter/assets', null);
      rootBundle.clear();
    });

    final catalog = await loadBundledCatalog();
    expect(catalog.varieties, hasLength(1));
    expect(catalog.varieties.single.name, 'Sun Gold');
    expect(catalog[catalog.varieties.single.cropId]!.name, 'Tomatoes');
  });

  test(
    'real bundled varieties load without skipped or orphaned entries',
    () async {
      final raw =
          jsonDecode(File('assets/catalog/varieties.json').readAsStringSync())
              as Map<String, dynamic>;
      final catalog = await loadBundledCatalog();
      expect(catalog.varieties, hasLength((raw['varieties'] as List).length));
      expect(catalog.varieties.length, greaterThan(1000));
      expect(
        catalog.varieties.map((v) => v.id).toSet(),
        hasLength(catalog.varieties.length),
      );
      expect(catalog.varieties.every((v) => catalog[v.cropId] != null), isTrue);
      expect(
        catalog.varieties.any((v) => catalog[v.cropId]!.category == 'Herbs'),
        isTrue,
      );
      expect(
        catalog.varieties.any(
          (v) => v.name == 'Sun Gold' && v.cropId == 'tomatoes',
        ),
        isTrue,
      );
    },
  );
}
