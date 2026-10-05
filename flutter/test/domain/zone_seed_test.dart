import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/ground.dart';

void main() {
  const seed = ZoneSeed(
    varietyId: 'v',
    name: 'Crop',
    inRow: 0.25,
    betweenRows: 0.75,
  );

  test('the two centre distances change independently', () {
    expect(seed.copyWith(inRow: 1).betweenRows, 0.75);
    expect(seed.copyWith(betweenRows: 1).inRow, 0.25);
    expect(seed.copyWith(), seed);
    expect(seed.copyWith().hashCode, seed.hashCode);
    expect(seed.copyWith(inRow: 1), isNot(seed));
    expect(seed.copyWith(betweenRows: 1), isNot(seed));
  });

  test('footprint is the closer spacing', () {
    expect(seed.footprint, 0.25);
    expect(seed.copyWith(inRow: 2).footprint, 0.75);
  });

  test('both spacings must be positive and finite', () {
    expect(seed.problem, isNull);
    for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
      expect(seed.copyWith(inRow: bad).problem, isNotNull);
      expect(seed.copyWith(betweenRows: bad).problem, isNotNull);
    }
  });
}
