import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/document_content.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/geometry.dart';

import '../support/editor_input.dart';
import '../support/first_shape.dart';

void main() {
  test(
    'saved content comparison includes bulges, holes and shape/circle labels',
    () {
      final (editor, input, layer) = property();
      rectangle(input, 0, 0, 10, 10);
      final before = editor.document;
      final geometry = before.geometryOf(layer);
      GardenDocument changed({
        Map<String, LineSegment>? lines,
        Map<String, ClosedShape>? shapes,
        Map<String, Circle>? circles,
      }) => before.withGeometry(
        Geometry(
          id: geometry.id,
          ownerLayerId: layer,
          points: geometry.points,
          lines: lines ?? geometry.lines,
          shapes: shapes ?? geometry.shapes,
          circles: circles ?? geometry.circles,
          order: geometry.order,
          counters: geometry.counters,
        ),
      );
      final line = geometry.lines.values.first;
      expect(
        sameContent(
          before,
          changed(
            lines: {
              ...geometry.lines,
              line.id: LineSegment(line.id, line.start, line.end, bulge: 0.1),
            },
          ),
        ),
        isFalse,
      );
      final shape = geometry.boundary!;
      expect(
        sameContent(
          before,
          changed(
            shapes: {
              shape.id: ClosedShape(shape.id, shape.segments, label: 'Beds'),
            },
          ),
        ),
        isFalse,
      );
      expect(
        sameContent(
          before,
          changed(
            shapes: {
              shape.id: ClosedShape(
                shape.id,
                shape.segments,
                holes: [shape.segments],
              ),
            },
          ),
        ),
        isFalse,
      );
      final first = changed(
        circles: {'circle-1': Circle('circle-1', line.start, 2)},
      );
      final second = changed(
        circles: {'circle-1': Circle('circle-1', line.start, 2, label: 'Beds')},
      );
      expect(sameContent(first, second), isFalse);
      expect(sameContent(before, changed()), isTrue);
    },
  );
}
