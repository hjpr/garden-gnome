import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/persistence/document_codec.dart';

import '../support/editor_input.dart';

void main() {
  group('soil sample', () {
    test('each value can be set or cleared, one Undo step each, and saved', () {
      final (editor, _, layer) = property();
      var p = editor.document.layers[layer]!.properties as PropertyProperties;
      editor.updateProperties(
        layer,
        p.copyWith(soil: p.soil.withValue('ph', 6.4)),
      );
      p = editor.document.layers[layer]!.properties as PropertyProperties;
      editor.updateProperties(
        layer,
        p.copyWith(soil: p.soil.withValue('organicMatter', 3.2)),
      );
      p = editor.document.layers[layer]!.properties as PropertyProperties;
      expect(p.soil.ph, 6.4);
      expect(p.soil.organicMatter, 3.2);
      expect(p.soil.potassium, isNull);

      final reopened = decodeGgnome(encodeGgnome(editor.document));
      final saved = reopened.layers[layer]!.properties as PropertyProperties;
      expect(saved.soil.ph, 6.4);
      expect(saved.soil.organicMatter, 3.2);

      editor.undo();
      p = editor.document.layers[layer]!.properties as PropertyProperties;
      expect(p.soil.organicMatter, isNull);
      expect(p.soil.ph, 6.4);
      expect(
        p.soil.withValue('ph', null).ph,
        isNull,
        reason: 'blank clears a value',
      );
    });
  });
}
