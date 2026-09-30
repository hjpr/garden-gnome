import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/grow/climate.dart';
import 'package:garden_gnome/domain/grow/crop.dart';
import 'package:garden_gnome/domain/grow/day.dart';
import 'package:garden_gnome/domain/grow/garden_record.dart';
import 'package:garden_gnome/domain/grow/planting.dart';
import 'package:garden_gnome/domain/grow/variety.dart';
import 'package:garden_gnome/persistence/garden_record_codec.dart';

Map<String, Object?> variety(String id, {String name = 'Salanova'}) => {
  'id': id,
  'crop': 'lettuce',
  'name': name,
};

String record({
  Object? version = gardenRecordVersion,
  Object? counter = 1,
  List<Object?> varieties = const [],
  List<Object?> plantings = const [],
}) => jsonEncode({
  'version': version,
  'counter': counter,
  'varieties': varieties,
  'plantings': plantings,
});

void main() {
  test('a record round-trips overrides, blanks and dates', () {
    final original = GardenRecord(
      counter: 2,
      climate: const Climate(
        zone: HardinessZone(5, 'b'),
        lastSpringFrost: MonthDay(5, 2),
      ),
      varieties: {
        'variety-1': const Variety(
          id: 'variety-1',
          cropId: 'lettuce',
          name: 'Salanova',
          daysToMaturity: IntRange(55, 55),
          sowing: SowingMethod.transplant,
          seedsOnHand: '1000 pellets',
          organic: true,
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
    );
    final back = decodeGardenRecord(encodeGardenRecord(original));
    final v = back.varieties['variety-1']!;
    expect(v.daysToMaturity, const IntRange(55, 55));
    expect(v.germinationDays, isNull);
    expect(v.sowing, SowingMethod.transplant);
    expect(v.seedsOnHand, '1000 pellets');
    expect(v.organic, isTrue);
    expect(back.climate.zone.code, '5b');
    expect(back.climate.lastSpringFrost, const MonthDay(5, 2));
    expect(back.climate.firstFallFrost, isNull);
    final p = back.plantings['planting-2']!;
    expect(p.sownOn, DateTime.utc(2026, 3, 20));
    expect(p.plantedOutOn, isNull);
    expect(p.count, 72);
    expect(back.counter, 2);
  });

  test('a record from a newer build is refused, not misread', () {
    expect(
      () => decodeGardenRecord(record(version: gardenRecordVersion + 1)),
      throwsA(
        isA<GardenRecordFormatError>().having(
          (e) => e.message,
          'message',
          contains('newer'),
        ),
      ),
    );
  });

  group('damaged records are refused rather than repaired', () {
    final damaged = <String, String>{
      'not JSON': '{',
      'not an object': '[]',
      'no version': jsonEncode({'counter': 0}),
      'version zero': record(version: 0),
      'a counter that is not a number': record(counter: 'one'),
      'two varieties with one ID': record(
        varieties: [
          variety('variety-1'),
          variety('variety-1', name: 'Other'),
        ],
      ),
      'a variety without a name': record(
        varieties: [
          {'id': 'variety-1', 'crop': 'lettuce'},
        ],
      ),
      'a range that is not a range': record(
        varieties: [
          {...variety('variety-1'), 'days_to_maturity': 'soon'},
        ],
      ),
      'an unknown sowing method': record(
        varieties: [
          {...variety('variety-1'), 'sowing': 'broadcast'},
        ],
      ),
      'a planting of a missing variety': record(
        plantings: [
          {
            'id': 'planting-1',
            'variety': 'variety-9',
            'sown': '2026-03-20',
            'indoors': true,
          },
        ],
      ),
      'a planting without a sowing date': record(
        varieties: [variety('variety-1')],
        plantings: [
          {'id': 'planting-2', 'variety': 'variety-1', 'indoors': false},
        ],
      ),
    };
    for (final MapEntry(key: name, value: text) in damaged.entries) {
      test(name, () {
        expect(
          () => decodeGardenRecord(text),
          throwsA(isA<GardenRecordFormatError>()),
        );
      });
    }
  });

  test('a counter behind its IDs is raised so no ID is issued twice', () {
    final back = decodeGardenRecord(
      record(counter: 0, varieties: [variety('variety-3')]),
    );
    final (_, id) = back.nextId('variety');
    expect(id, 'variety-4');
  });

  test('absent optional values stay absent', () {
    final back = decodeGardenRecord(record(varieties: [variety('variety-1')]));
    final v = back.varieties['variety-1']!;
    expect(v.source, isNull);
    expect(v.yearPacked, isNull);
    expect(v.organic, isFalse);
    expect(v.notes, '');
    expect(back.climate.zone, HardinessZone.fallback);
  });
}
