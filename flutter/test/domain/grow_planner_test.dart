import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/grow/climate.dart';
import 'package:garden_gnome/domain/grow/crop.dart';
import 'package:garden_gnome/domain/grow/day.dart';
import 'package:garden_gnome/domain/grow/planting.dart';
import 'package:garden_gnome/domain/grow/planting_windows.dart';
import 'package:garden_gnome/domain/grow/variety.dart';

import '../support/grow_fixtures.dart';

VarietyProfile _profile(Crop crop, {Variety? variety}) =>
    (variety ?? Variety(id: 'v-${crop.id}', cropId: crop.id, name: crop.name))
        .resolve(crop);

DateTime _d(int m, int d) => DateTime.utc(2026, m, d);

void main() {
  // Zone 6a: last spring frost Apr 23, first fall frost Oct 15.
  const climate = Climate(zone: HardinessZone(6, 'a'));
  const planner = PlantingPlanner(climate);

  test('zone halves shift the frost dates five days', () {
    expect(const HardinessZone(6, 'a').lastSpringFrost, const MonthDay(4, 23));
    expect(const HardinessZone(6, 'b').lastSpringFrost, const MonthDay(4, 13));
    expect(const HardinessZone(6, 'a').firstFallFrost, const MonthDay(10, 15));
    expect(
      const Climate(lastSpringFrost: MonthDay(5, 1)).springFrost,
      const MonthDay(5, 1),
      reason: 'the gardener’s own date wins over the zone’s',
    );
  });

  test('tomatoes: plant out after frost, start in the greenhouse earlier', () {
    final windows = planner.windowsFor(_profile(testTomato), 2026);
    final out = windows.singleWhere((w) => w.kind == WindowKind.plantOut);
    final sow = windows.singleWhere((w) => w.kind == WindowKind.greenhouseSow);
    expect(windows.where((w) => w.kind == WindowKind.directSow), isEmpty);

    // Ideal 1–4 weeks after Apr 23.
    expect(out.ideal, DayWindow(_d(4, 30), _d(5, 21)));
    expect(out.timingOn(_d(4, 25)), Timing.early);
    expect(out.timingOn(_d(5, 10)), Timing.ideal);
    expect(out.timingOn(_d(6, 15)), Timing.late);
    expect(out.timingOn(_d(3, 1)), Timing.upcoming);
    // Late enough that 75 days to maturity ends two weeks before frost.
    expect(out.span.end, addDays(_d(10, 1), -75));
    expect(out.timingOn(addDays(out.span.end, 1)), Timing.passed);

    // Greenhouse sowing is the same window moved back six weeks.
    expect(sow.ideal.start, addDays(out.ideal.start, -42));
    expect(sow.timingOn(_d(3, 25)), Timing.ideal);
  });

  test('lettuce gets a spring window and a fall window', () {
    final direct = planner
        .windowsFor(_profile(testLettuce), 2026)
        .where((w) => w.kind == WindowKind.directSow)
        .toList();
    expect(direct.map((w) => w.season), [
      PlantingSeason.spring,
      PlantingSeason.fall,
    ]);
    final spring = direct.first, fall = direct.last;
    expect(spring.ideal.start, _d(3, 26)); // Four weeks before frost.
    expect(spring.span.end, addDays(spring.ideal.end, 21));
    expect(fall.span.start.isAfter(spring.span.end), isTrue);
    // Half-hardy: matures by the frost date itself.
    expect(fall.span.end, addDays(_d(10, 15), -50));
  });

  test('a variety value overrides its crop', () {
    final quick = _profile(
      testTomato,
      variety: const Variety(
        id: 'v',
        cropId: 'tomatoes',
        name: 'Early Girl',
        daysToMaturity: IntRange(50, 50),
      ),
    );
    expect(quick.daysToMaturity, const IntRange(50, 50));
    expect(quick.inRowSpacingIn, testTomato.inRowSpacingIn);
    final out = planner
        .windowsFor(quick, 2026)
        .singleWhere((w) => w.kind == WindowKind.plantOut);
    expect(out.span.end, addDays(_d(10, 1), -50));
  });

  test('recommendations look a year ahead, open ones first', () {
    final profiles = [
      _profile(testTomato),
      _profile(testLettuce),
      _profile(testBean),
    ];
    final found = recommend(profiles, planner, _d(4, 1));
    expect(found, isNotEmpty);
    expect(found.first.timing.isOpen, isTrue);
    final timings = found.map((r) => r.timing).toList();
    final firstClosed = timings.indexWhere((t) => !t.isOpen);
    if (firstClosed >= 0) {
      expect(timings.skip(firstClosed).every((t) => !t.isOpen), isTrue);
    }
    // Beans go in a week after frost: upcoming on Apr 1, within reach.
    final beans = found.where((r) => r.profile.crop == testBean).single;
    expect(beans.timing, Timing.upcoming);

    // Every variety shows, even when its window is months away: in
    // October, next spring's tomato window.
    final october = recommend(profiles, planner, _d(10, 3));
    expect(october.map((r) => r.profile.crop).toSet(), {
      testTomato,
      testLettuce,
      testBean,
    });
    expect(
      october.every(
        (r) => !r.window.span.start.isAfter(addDays(_d(10, 3), 365)),
      ),
      isTrue,
    );
    expect(october.where((r) => r.timing == Timing.passed), isEmpty);

    // In late September nothing warm-season is left to sow.
    final fall = recommend(profiles, planner, _d(9, 29));
    expect(
      fall.where((r) => r.profile.crop == testTomato && r.timing.isOpen),
      isEmpty,
    );
  });

  test('planting schedule: greenhouse, plant out, harvest', () {
    final tomato = _profile(testTomato);
    final sown = Planting(
      id: 'p',
      varietyId: tomato.id,
      sownOn: _d(3, 20),
      startedIndoors: true,
    );
    final s = PlantingSchedule(sown, tomato);
    expect(sown.stage, PlantingStage.greenhouse);
    expect(s.germination, DayWindow(_d(3, 25), _d(3, 27)));
    expect(s.plantOut, DayWindow(_d(4, 24), _d(5, 1)));
    // Not out yet: assumes it goes out after the typical 6 weeks.
    expect(s.harvest.start, addDays(_d(5, 1), 75));

    final out = sown.copyWith(plantedOutOn: () => _d(5, 10));
    expect(out.stage, PlantingStage.inGround);
    final h = PlantingSchedule(out, tomato).harvest;
    expect(h.start, addDays(_d(5, 10), 75));
    expect(h.end, addDays(h.start, 75));
  });

  test('direct sowing a crop timed from transplant adds greenhouse time', () {
    final lettuce = _profile(testLettuce);
    expect(lettuce.daysFromDirectSowing, 50);
    // 50 − 28 days in trays would be 22; never less than half of 50.
    expect(lettuce.daysFromTransplant, 25);
    final tomato = _profile(testTomato);
    expect(tomato.daysFromTransplant, 75);
    expect(tomato.daysFromDirectSowing, 75 + 28);
  });

  test('garlic is planted around the first fall frost to overwinter', () {
    final garlic = Crop(
      id: 'garlic',
      name: 'Garlic',
      category: 'Vegetables',
      season: Season.cool,
      frostTolerance: FrostTolerance.hardy,
      sowing: SowingMethod.direct,
      daysToMaturity: const IntRange(240, 270),
      plantOutWeeks: const IntRange(-6, -2),
      overwinterWeeks: const IntRange(-2, 4),
      inRowSpacingIn: const LengthRange(4, 6),
      betweenRowSpacingIn: const LengthRange(12, 18),
      harvestWindowDays: const IntRange(7, 14),
    );
    final w = planner
        .windowsFor(_profile(garlic), 2026)
        .singleWhere((w) => w.season == PlantingSeason.overwinter);
    expect(w.ideal, DayWindow(_d(10, 1), _d(11, 12)));
    expect(w.timingOn(_d(9, 29)), Timing.early);
    expect(w.timingOn(_d(10, 20)), Timing.ideal);
  });
}
