import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/layer.dart';

void main() {
  test('every listed field reads and writes its own value', () {
    var soil = const SoilSample();
    for (final (i, (field, _)) in SoilSample.fields.indexed) {
      soil = soil.withValue(field, i + 1.0);
    }
    for (final (i, (field, _)) in SoilSample.fields.indexed) {
      expect(soil.valueOf(field), i + 1.0, reason: field);
    }
  });
}
