import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/item_bounds.dart';
import 'package:garden_gnome/application/transform_box.dart';
import 'package:garden_gnome/domain/geometry.dart';
import 'package:garden_gnome/domain/geometry_editor.dart';
import 'package:garden_gnome/domain/vec.dart';

void main() {
  test(
    'Align keeps open-shape point bounds while transform requires closure',
    () {
      final closed = Geometry(id: 'g', ownerLayerId: 'layer').edit((e) {
        final ids = [
          for (final p in const [
            Vec(0, 0),
            Vec(10, 0),
            Vec(10, 10),
            Vec(0, 10),
          ])
            e.addPoint(p),
        ];
        for (var i = 0; i < ids.length; i++) {
          e.connect(ids[i], ids[(i + 1) % ids.length]);
        }
      });
      final shape = closed.stack.single;
      expect(TransformBox.around(closed, [shape]), isNotNull);
      final open = closed.edit((e) => e.delete([closed.lines.keys.first]));
      expect(boundsOfItem(open, shape), (Vec.zero, const Vec(10, 10)));
      expect(boundsOfItem(open, shape, includeOpenShapes: false), isNull);
      expect(TransformBox.around(open, [shape]), isNull);
    },
  );

  test('a point has bounds for Align but not a transform box by itself', () {
    final geometry = Geometry(
      id: 'g',
      ownerLayerId: 'layer',
      points: const {'point-1': Vec(2, 3)},
    );
    expect(boundsOfItem(geometry, 'point-1'), (
      const Vec(2, 3),
      const Vec(2, 3),
    ));
    expect(TransformBox.around(geometry, ['point-1']), isNull);
    expect(boundsOfItem(geometry, 'missing'), isNull);
    expect(unionBounds([]), isNull);
  });
}
