import 'day.dart';

/// A USDA plant hardiness zone, such as 6b.
///
/// Used only to guess average frost dates, which is all the planting
/// calendar needs. The gardener can override either date.
class HardinessZone {
  const HardinessZone(this.number, this.half)
    : assert(number >= 1 && number <= 13),
      assert(half == 'a' || half == 'b');

  final int number;

  /// "a" is the colder half of the zone, "b" the warmer.
  final String half;

  static const fallback = HardinessZone(6, 'a');

  /// Every zone from 1a to 13b, coldest first.
  static final List<HardinessZone> all = List.unmodifiable([
    for (var n = 1; n <= 13; n++) ...[
      HardinessZone(n, 'a'),
      HardinessZone(n, 'b'),
    ],
  ]);

  String get code => '$number$half';

  static HardinessZone? tryParse(Object? value) {
    if (value is! String) return null;
    final match = RegExp(r'^(\d{1,2})([ab])$').firstMatch(value.trim());
    if (match == null) return null;
    final n = int.parse(match[1]!);
    if (n < 1 || n > 13) return null;
    return HardinessZone(n, match[2]!);
  }

  /// Zones 11 and warmer do not normally see frost.
  bool get frostFree => number >= 11;

  /// Typical average last spring frost for the zone.
  MonthDay get lastSpringFrost =>
      _shift(_zoneFrost[number]!.$1, half == 'a' ? 5 : -5);

  /// Typical average first fall frost for the zone.
  MonthDay get firstFallFrost =>
      _shift(_zoneFrost[number]!.$2, half == 'a' ? -5 : 5);

  @override
  String toString() => 'Zone $code';

  @override
  bool operator ==(Object other) =>
      other is HardinessZone && other.number == number && other.half == half;

  @override
  int get hashCode => Object.hash(number, half);
}

/// Middle-of-zone average frost dates (last spring, first fall), from the
/// usual extension-service tables. Frost-free zones use the year's ends
/// so every crop's window is open.
const _zoneFrost = <int, (MonthDay, MonthDay)>{
  1: (MonthDay(6, 5), MonthDay(8, 25)),
  2: (MonthDay(5, 25), MonthDay(9, 5)),
  3: (MonthDay(5, 15), MonthDay(9, 15)),
  4: (MonthDay(5, 8), MonthDay(9, 28)),
  5: (MonthDay(4, 28), MonthDay(10, 8)),
  6: (MonthDay(4, 18), MonthDay(10, 20)),
  7: (MonthDay(4, 6), MonthDay(10, 30)),
  8: (MonthDay(3, 22), MonthDay(11, 12)),
  9: (MonthDay(2, 25), MonthDay(12, 1)),
  10: (MonthDay(1, 25), MonthDay(12, 20)),
  11: (MonthDay(1, 6), MonthDay(12, 26)),
  12: (MonthDay(1, 6), MonthDay(12, 26)),
  13: (MonthDay(1, 6), MonthDay(12, 26)),
};

MonthDay _shift(MonthDay base, int days) {
  final d = addDays(base.inYear(2001), days); // A non-leap year.
  return MonthDay(d.month, d.day);
}

/// Where the garden is, as far as planting dates care.
class Climate {
  const Climate({
    this.zone = HardinessZone.fallback,
    this.lastSpringFrost,
    this.firstFallFrost,
  });

  final HardinessZone zone;

  /// The gardener's own frost dates; null uses the zone's.
  final MonthDay? lastSpringFrost;
  final MonthDay? firstFallFrost;

  MonthDay get springFrost => lastSpringFrost ?? zone.lastSpringFrost;
  MonthDay get fallFrost => firstFallFrost ?? zone.firstFallFrost;

  Climate copyWith({
    HardinessZone? zone,
    MonthDay? Function()? lastSpringFrost,
    MonthDay? Function()? firstFallFrost,
  }) => Climate(
    zone: zone ?? this.zone,
    lastSpringFrost: lastSpringFrost == null
        ? this.lastSpringFrost
        : lastSpringFrost(),
    firstFallFrost: firstFallFrost == null
        ? this.firstFallFrost
        : firstFallFrost(),
  );
}
