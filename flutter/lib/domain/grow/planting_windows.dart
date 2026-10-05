import 'climate.dart';
import 'crop.dart';
import 'day.dart';
import 'daylight.dart';
import 'variety.dart';

/// What a planting window is for.
enum WindowKind {
  /// Sow the seed where it will grow.
  directSow('Direct sow'),

  /// Sow in trays in the greenhouse, to plant out later.
  greenhouseSow('Start in greenhouse'),

  /// Plant greenhouse transplants out into the ground.
  plantOut('Plant out');

  const WindowKind(this.label);

  final String label;
}

/// Spring or fall, or one of the winter options.
enum PlantingSeason {
  spring('Spring'),
  fall('Fall'),

  /// Sown late summer or fall to harvest through winter.
  winterHarvest('Winter harvest'),

  /// Planted in fall to grow on through winter, e.g. garlic.
  overwinter('Overwinter');

  const PlantingSeason(this.label);

  final String label;
}

/// How a date sits against a planting window.
enum Timing {
  /// Before the window opens.
  upcoming('Upcoming'),

  /// Possible now, but ahead of the best time: more frost or cold risk.
  early('Early'),

  /// The best time.
  ideal('Ideal'),

  /// Possible now, but past the best time: less season left to mature.
  late('Late'),

  /// The window has closed.
  passed('Passed');

  const Timing(this.label);

  final String label;

  /// Whether sowing or planting today is possible at all.
  bool get isOpen => this == early || this == ideal || this == late;
}

/// One stretch of the year when a variety can be sown or planted, with
/// its best part marked. [ideal] always lies inside [span].
class PlantingWindow {
  PlantingWindow({
    required this.profile,
    required this.kind,
    required this.season,
    required this.span,
    required this.ideal,
    this.structure,
    this.winter,
  });

  final VarietyProfile profile;
  final WindowKind kind;
  final PlantingSeason season;

  /// The protection this window needs, e.g. a high tunnel; null for the
  /// usual open-field windows.
  final Structure? structure;

  /// The Johnny's winter chart row this window came from, if any.
  final WinterWindow? winter;

  /// An alternate to the usual open-field sowing: it needs protection.
  bool get isAlternate => structure != null;

  /// "Spring", or "Winter harvest · needs high tunnel · baby leaf".
  String get label => [
    season.label,
    if (structure case final s?) 'needs ${s.label}',
    ?winter?.detail,
  ].join(' · ');

  /// From the earliest to the latest sensible day.
  final DayWindow span;

  /// The best days.
  final DayWindow ideal;

  Timing timingOn(DateTime day) {
    final d = dayOf(day);
    if (d.isBefore(span.start)) return Timing.upcoming;
    if (d.isAfter(span.end)) return Timing.passed;
    if (d.isBefore(ideal.start)) return Timing.early;
    if (d.isAfter(ideal.end)) return Timing.late;
    return Timing.ideal;
  }

  /// Days until the ideal part starts (negative once it has started).
  int daysToIdeal(DateTime day) => daysBetween(day, ideal.start);

  /// This window moved by [days], e.g. back by the greenhouse weeks.
  PlantingWindow shifted(WindowKind kind, int days) => PlantingWindow(
    profile: profile,
    kind: kind,
    season: season,
    span: span.shift(days, days),
    ideal: ideal.shift(days, days),
    structure: structure,
    winter: winter,
  );
}

/// Works out when each variety can be sown and planted, from its crop's
/// catalog values and the garden's frost dates.
///
/// Rules, all guesses a gardener can override by editing the variety:
/// - Spring: the crop's plant-out weeks around the last spring frost are
///   ideal. Hardy crops may go in two weeks earlier, others one.
/// - The latest day is the one that still lets the crop mature before the
///   first fall frost (tender crops two weeks before it, hardy crops two
///   weeks after it).
/// - Warm-season crops can keep going in until that latest day; cool
///   crops bolt in summer heat, so their spring window closes three weeks
///   after its ideal part.
/// - Cool crops the catalog marks for fall get a second window ending on
///   the latest day, ideal for its first four weeks.
/// - Crops that overwinter (garlic) get a window around the first fall
///   frost from the catalog, open a week before and two after its best
///   part.
/// - Greenhouse sowing windows are the plant-out windows moved back by
///   the weeks transplants spend in trays.
/// - Alternates from Johnny's winter charts (winter harvest in a high
///   tunnel, overwintering under low tunnels) are timed in weeks before
///   the last day with 10 hours of daylight, so they need the farm's
///   latitude; sowings to transplant are greenhouse windows.
class PlantingPlanner {
  const PlantingPlanner(this.climate);

  final Climate climate;

  /// Every window of [profile] in [year]'s growing season.
  List<PlantingWindow> windowsFor(VarietyProfile profile, int year) {
    final windows = <PlantingWindow>[];
    final sowing = profile.sowing;
    if (sowing.canDirectSow) {
      windows.addAll(
        _groundWindows(
          profile,
          year,
          WindowKind.directSow,
          profile.daysFromDirectSowing,
        ),
      );
    }
    if (profile.crop.overwinterWeeks case final weeks?
        when sowing.canDirectSow) {
      final frost = climate.fallFrost.inYear(year);
      final ideal = DayWindow(
        addDays(frost, weeks.min * 7),
        addDays(frost, weeks.max * 7),
      );
      windows.add(
        PlantingWindow(
          profile: profile,
          kind: WindowKind.directSow,
          season: PlantingSeason.overwinter,
          span: ideal.shift(-7, 14),
          ideal: ideal,
        ),
      );
    }
    if (sowing.canTransplant) {
      final out = _groundWindows(
        profile,
        year,
        WindowKind.plantOut,
        profile.daysFromTransplant,
      );
      windows.addAll(out);
      final back = -profile.weeksToTransplant.mid * 7;
      windows.addAll([
        for (final w in out) w.shifted(WindowKind.greenhouseSow, back),
      ]);
    }
    windows.addAll(_winterWindows(profile, year));
    return windows;
  }

  /// [profile]'s winter chart windows for the short days starting in the
  /// fall of [year]. None without a latitude, or where days never drop
  /// under 10 hours.
  List<PlantingWindow> _winterWindows(VarietyProfile profile, int year) {
    final latitude = climate.latitude;
    final rows = profile.crop.winterWindows;
    if (latitude == null || rows.isEmpty) return const [];
    final dark = shortDays(latitude, year);
    if (dark == null) return const [];
    final last10 = addDays(dark.start, -1);
    return [
      for (final w in rows)
        // Week N on the chart is the 7 days from N weeks before.
        if (DayWindow(
              addDays(last10, -w.weeksBefore.max * 7),
              addDays(last10, -w.weeksBefore.min * 7 + 6),
            )
            case final span)
          PlantingWindow(
            profile: profile,
            kind: w.transplant
                ? WindowKind.greenhouseSow
                : WindowKind.directSow,
            season: w.use == WinterUse.winterHarvest
                ? PlantingSeason.winterHarvest
                : PlantingSeason.overwinter,
            span: span,
            ideal: span,
            structure: w.structure,
            winter: w,
          ),
    ];
  }

  /// Windows for putting [profile] in the ground (as seed or transplant)
  /// when it then takes [daysToHarvest] to mature.
  List<PlantingWindow> _groundWindows(
    VarietyProfile profile,
    int year,
    WindowKind kind,
    int daysToHarvest,
  ) {
    final crop = profile.crop;
    final spring = climate.springFrost.inYear(year);
    var fall = climate.fallFrost.inYear(year);
    if (!fall.isAfter(spring)) fall = climate.fallFrost.inYear(year + 1);

    final weeks = crop.plantOutWeeks;
    final idealStart = addDays(spring, weeks.min * 7);
    final idealEnd = addDays(spring, weeks.max * 7);
    final earlyDays = crop.frostTolerance == FrostTolerance.hardy ? 14 : 7;
    final latest = addDays(
      fall,
      -crop.frostTolerance.fallMarginDays - daysToHarvest,
    );

    final springEnd = crop.season == Season.warm
        ? latest
        : _earlier(addDays(idealEnd, 21), latest);
    final windows = <PlantingWindow>[];
    if (!springEnd.isBefore(idealStart)) {
      windows.add(
        PlantingWindow(
          profile: profile,
          kind: kind,
          season: PlantingSeason.spring,
          span: DayWindow(addDays(idealStart, -earlyDays), springEnd),
          ideal: DayWindow(idealStart, _earlier(idealEnd, springEnd)),
        ),
      );
    }

    if (crop.season == Season.cool && crop.fallCrop) {
      final start = _later(addDays(latest, -42), addDays(springEnd, 1));
      if (!latest.isBefore(start)) {
        windows.add(
          PlantingWindow(
            profile: profile,
            kind: kind,
            season: PlantingSeason.fall,
            span: DayWindow(start, latest),
            ideal: DayWindow(start, _earlier(addDays(start, 27), latest)),
          ),
        );
      }
    }
    return windows;
  }
}

DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

/// One thing to do, for the Grow and Greenhouse lists.
class Recommendation {
  Recommendation(this.window, this.today);

  final PlantingWindow window;
  final DateTime today;

  Timing get timing => window.timingOn(today);
  VarietyProfile get profile => window.profile;
}

/// Recommendations for [profiles]: every window open now or opening
/// within [aheadDays] of [today] (a year by default, so every variety
/// shows its next chance), in order of urgency: open windows first
/// (ideal, then late, then early), then upcoming ones soonest first.
List<Recommendation> recommend(
  Iterable<VarietyProfile> profiles,
  PlantingPlanner planner,
  DateTime today, {
  Set<WindowKind> kinds = const {...WindowKind.values},
  int aheadDays = 365,
}) {
  final reach = DayWindow(today, addDays(today, aheadDays));
  final found = <Recommendation>[];
  for (final profile in profiles) {
    for (var year = today.year - 1; year <= today.year + 1; year++) {
      for (final w in planner.windowsFor(profile, year)) {
        if (kinds.contains(w.kind) && w.span.overlaps(reach)) {
          found.add(Recommendation(w, today));
        }
      }
    }
  }
  int rank(Timing t) => switch (t) {
    Timing.ideal => 0,
    Timing.late => 1,
    Timing.early => 2,
    Timing.upcoming => 3,
    Timing.passed => 4,
  };
  found.sort((a, b) {
    final byTiming = rank(a.timing) - rank(b.timing);
    if (byTiming != 0) return byTiming;
    final byStart = a.window.span.start.compareTo(b.window.span.start);
    if (a.timing == Timing.passed) return -byStart; // Most recent first.
    if (byStart != 0) return byStart;
    return a.profile.displayName.compareTo(b.profile.displayName);
  });
  return found;
}
