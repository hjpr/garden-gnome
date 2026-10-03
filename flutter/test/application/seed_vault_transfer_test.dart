import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/garden_controller.dart';
import 'package:garden_gnome/application/toasts.dart';
import 'package:garden_gnome/domain/grow/variety.dart';
import 'package:garden_gnome/persistence/garden_record_codec.dart';

import '../support/grow_fixtures.dart';
import '../support/memory_garden_record_store.dart';

Future<GardenController> _garden() async {
  final garden = GardenController(
    store: MemoryGardenRecordStore(),
    toasts: ToastCenter(),
    catalog: testCatalog,
  );
  await garden.load();
  return garden;
}

void main() {
  test('an exported vault imports into another with new IDs', () async {
    final source = await _garden();
    final id = source.addVariety('tomatoes', 'Big Beef');
    source.updateVariety(
      source.record.varieties[id]!.copyWith(notes: 'Staked'),
    );
    source.addVariety('lettuce', 'Buttercrunch');
    final text = encodeSeedVault(source.record.varieties.values);
    expect(text, isNot(contains('planting')));

    final target = await _garden();
    target.addVariety('lettuce', 'Buttercrunch');
    final (added, skipped) = target.importVarieties(decodeSeedVault(text));
    expect((added, skipped), (1, 1), reason: 'Buttercrunch is already here');
    final beef = target.record.varieties.values.firstWhere(
      (v) => v.name == 'Big Beef',
    );
    expect(beef.notes, 'Staked');
    expect(target.record.varieties.length, 2);
    expect(target.record.varieties.keys.toSet().length, 2);

    expect(target.importVarieties(decodeSeedVault(text)), (0, 2));
  });

  test('unknown crops are skipped and other files are refused', () async {
    final garden = await _garden();
    final (added, skipped) = garden.importVarieties(const [
      Variety(id: 'variety-9', cropId: 'not-a-crop', name: 'Mystery'),
    ]);
    expect((added, skipped), (0, 1));
    expect(garden.record.varieties, isEmpty);
    for (final text in ['nope', '{}', '{"format":"garden-gnome"}']) {
      expect(
        () => decodeSeedVault(text),
        throwsA(isA<GardenRecordFormatError>()),
      );
    }
    expect(
      () => decodeSeedVault(
        '{"format":"garden-gnome-seed-vault","version":99,"varieties":[]}',
      ),
      throwsA(isA<GardenRecordFormatError>()),
    );
  });
}
