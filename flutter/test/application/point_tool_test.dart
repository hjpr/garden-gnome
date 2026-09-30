import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/tools.dart';

import '../support/editor_input.dart';

void main() {
  group('point spacing', () {
    test('a new point too close to another is refused with a reason', () {
      final (editor, input, layer) = property();
      editor.selectTool(Tool.point);
      click(input, 5, 5);
      final before = editor.document;
      // Less than one 6 px marker away.
      final nudge = editor.camera.metres(3);
      click(input, 5 + nudge, 5);
      expect(identical(editor.document, before), isTrue);
      expect(editor.notice, contains('Too close'));
      click(input, 6, 5);
      expect(editor.document.geometryOf(layer).points, hasLength(2));
    });
  });
}
