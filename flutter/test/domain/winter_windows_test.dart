import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/grow/climate.dart';
import 'package:garden_gnome/domain/grow/crop.dart';
import 'package:garden_gnome/domain/grow/day.dart';
import 'package:garden_gnome/domain/grow/daylight.dart';
import 'package:garden_gnome/domain/grow/planting_windows.dart';
import 'package:garden_gnome/domain/grow/variety.dart';
import 'package:garden_gnome/persistence/crop_catalog_codec.dart';
import 'package:garden_gnome/persistence/garden_record_codec.dart';

import '../support/grow_fixtures.dart';

/// Lettuce with Johnny's winter-harvest rows: full heads started as
/// transplants 10–11 weeks before the last 10-hour day, baby leaf sown in
/// place 6–7 weeks before.
final _winterLettuce = Crop(
  id: 'lettuce',
  name: 'Lettuce',
  category: 'Vegetables',
  season: testLettuce.season,
  frostTolerance: testLettuce.frostTolerance,
  sowing: testLettuce.sowing,
  daysToMaturity: testLettuce.daysToMaturity,
  plantOutWeeks: testLettuce.plantOutWeeks,
  inRowSpacingIn: testLettuce.inRowSpacingIn,
  betweenRowSpacingIn: testLettuce.betweenRowSpacingIn,
  harvestWindowDays: testLettuce.harvestWindowDays,
  winterWindows: const [
    WinterWindow(
      use: WinterUse.winterHarvest,
      structure: Structure.highTunnel,
      transplant: true,
      weeksBefore: IntRange(10, 11),
      tier: 3,
    ),
    WinterWindow(
      use: WinterUse.winterHarvest,
      structure: Structure.highTunnel,
      transplant: false,
      weeksBefore: IntRange(6, 7),
      tier: 3,
      detail: 'baby leaf',
    ),
  ],
);

VarietyProfile get _profile => const Variety(
  id: 'v',
  cropId: 'lettuce',
  name: 'Little Gem',
).resolve(_winterLettuce);

void main() {
  test('day length and the 10-hour short days follow latitude', () {
    // Johnny's farm (44.5°N) puts the short days at about Nov 6 – Feb 6.
    final maine = shortDays(44.5, 2026)!;
    expect(
      maine.start.difference(DateTime.utc(2026, 11, 6)).inDays.abs(),
      lessThanOrEqualTo(4),
    );
    expect(
      maine.end.difference(DateTime.utc(2027, 2, 6)).inDays.abs(),
      lessThanOrEqualTo(4),
    );
    // Further south the dark stretch is shorter; far enough south it
    // never comes.
    expect(shortDays(38, 2026)!.start.isAfter(maine.start), isTrue);
    expect(shortDays(30, 2026), isNull);
    // South of the equator the short days fall around the June solstice.
    final south = shortDays(-44.5, 2026)!;
    expect(south.contains(DateTime.utc(2026, 6, 21)), isTrue);
    expect(dayLength(44.5, DateTime.utc(2026, 6, 21)), greaterThan(15));
  });

  test('winter windows are dated from the last 10-hour day, need a high '
      'tunnel, and need the latitude', () {
    expect(
      const PlantingPlanner(
        Climate(),
      ).windowsFor(_profile, 2026).where((w) => w.isAlternate),
      isEmpty,
      reason: 'no latitude, no winter dates',
    );
    const climate = Climate(zone: HardinessZone(6, 'a'), latitude: 44.5);
    final winter = const PlantingPlanner(climate)
        .windowsFor(_profile, 2026)
        .where((w) => w.season == PlantingSeason.winterHarvest)
        .toList();
    expect(winter, hasLength(2));
    final last10 = addDays(shortDays(44.5, 2026)!.start, -1);
    final heads = winter.firstWhere((w) => w.kind == WindowKind.greenhouseSow);
    expect(heads.span.start, addDays(last10, -77));
    expect(heads.span.end, addDays(last10, -70 + 6));
    expect(heads.structure, Structure.highTunnel);
    expect(heads.label, 'Winter harvest · needs high tunnel');
    final baby = winter.firstWhere((w) => w.kind == WindowKind.directSow);
    expect(baby.label, 'Winter harvest · needs high tunnel · baby leaf');
    // The usual open-field windows are still there and not alternates.
    expect(
      const PlantingPlanner(climate)
          .windowsFor(_profile, 2026)
          .where((w) => w.season == PlantingSeason.spring)
          .every((w) => !w.isAlternate),
      isTrue,
    );
  });

  test('the catalog reads winter windows and skips unreadable ones', () {
    final catalog = decodeCropCatalog('''
{"crops": [{"id": "kale", "name": "Kale", "season": "cool",
  "frostTolerance": "hardy", "sowing": "either",
  "daysToMaturity": [50, 65], "plantOutWeeks": [-4, -2],
  "inRowSpacingIn": [12, 18], "betweenRowSpacingIn": [18, 30],
  "winterWindows": [
    {"use": "overwinter", "structure": "lowTunnel", "method": "direct",
     "weeksBefore": [1, 3], "tier": 1, "detail": "baby leaf"},
    {"use": "springtime", "structure": "lowTunnel", "method": "direct",
     "weeksBefore": [1, 3]}
  ]}]}
''');
    final w = catalog['kale']!.winterWindows.single;
    expect(w.use, WinterUse.overwinter);
    expect(w.structure, Structure.lowTunnel);
    expect(w.transplant, isFalse);
    expect(w.weeksBefore, const IntRange(1, 3));
    expect(w.tierLabel, 'most reliable');
  });

  test('the farm keeps its latitude and refuses an impossible one', () {
    const climate = Climate(latitude: 42.25);
    expect(climateFromJson(climateToJson(climate)).latitude, 42.25);
    expect(climateFromJson(climateToJson(const Climate())).latitude, isNull);
    expect(
      () => climateFromJson({'zone': '6a', 'latitude': 120}),
      throwsFormatException,
    );
  });
}
