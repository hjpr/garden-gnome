import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/ground.dart';

void main() {
  const seed = ZoneSeed(varietyId: 'v', name: 'Crop', size: 0.5, spacing: 0.25);

  test('size and empty spacing determine pitch independently', () {
    expect(seed.pitch, 0.75);
    expect(seed.copyWith(size: 1).pitch, 1.25);
    expect(seed.copyWith(spacing: 1).size, 0.5);
    expect(seed.copyWith(spacing: 1).pitch, 1.5);
    expect(seed.copyWith(), seed);
    expect(seed.copyWith().hashCode, seed.hashCode);
    expect(seed.copyWith(size: 1), isNot(seed));
    expect(seed.copyWith(spacing: 1), isNot(seed));
  });

  test('zero gap is valid but negative or nonfinite gaps are not', () {
    expect(seed.copyWith(spacing: 0).problem, isNull);
    for (final gap in [-0.01, double.nan, double.infinity, double.negativeInfinity]) {
      expect(seed.copyWith(spacing: gap).problem, isNotNull);
    }
  });

  test('diameter must be positive and total pitch finite', () {
    for (final size in [0.0, -1.0, double.nan, double.infinity]) {
      expect(seed.copyWith(size: size).problem, isNotNull);
    }
    expect(seed.copyWith(size: 1e308, spacing: 1e308).problem, isNotNull);
  });
}
