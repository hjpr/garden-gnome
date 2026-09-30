import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/units.dart';

void main() {
  test('Net area uses squared unit conversion and a dash for open land', () {
    expect(AreaUnits.squareMetres.format(null), '—');
    expect(AreaUnits.squareMetres.format(12.5), '12.5 m²');
    expect(AreaUnits.squareFeet.format(0.3048 * 0.3048), '1 ft²');
    expect(AreaUnits.squareMetres.format(0), '0 m²');
    expect(AreaUnits.acres.format(4046.8564224), '1 acre');
    expect(AreaUnits.acres.format(100), '0.0247 acres');
  });
}
