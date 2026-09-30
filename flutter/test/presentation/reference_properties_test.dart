import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/units.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/presentation/panels/layers_panel.dart';
import 'package:garden_gnome/presentation/panels/properties_panel.dart';
import '../support/widget_harness.dart';
import 'package:garden_gnome/presentation/widgets/text_focus.dart';

final png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
]);

Widget harness(EditorController editor) => editorPanel(
  editor: editor,
  builder: (context) => PropertiesBody(editor: editor),
);

void main() {
  testWidgets('typing a distance and pressing Enter calibrates the image', (
    tester,
  ) async {
    final editor = EditorController()..setViewportSize(const Size(800, 600));
    addTearDown(editor.dispose);
    editor.updateSettings(editor.settings.copyWith(units: Units.feet));
    editor.selectTool(Tool.reference);
    await tester.pumpWidget(harness(editor));
    // Same layout with nothing uploaded, just greyed out.
    expect(find.text('Upload image'), findsOneWidget);
    expect(find.text('No image selected'), findsOneWidget);
    expect(find.text('Opacity'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    editor.addReferenceImage(
      bytes: png,
      mimeType: 'image/png',
      pixelWidth: 400,
      pixelHeight: 200,
    );
    await tester.pumpAndSettle();
    expect(find.text('Opacity'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('Distance (ft)'), findsOneWidget);

    final image = editor.selectedImage!;
    editor.updateReference(
      'Reference line',
      image.withLine(const Vec(0, 0), const Vec(200, 0)),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

    await tester.enterText(find.byType(TextField), '60');
    // The box owns the keyboard, so editor shortcuts leave Enter alone.
    expect(textFieldHasFocus(), isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final calibrated = editor.selectedImage!;
    expect(calibrated.lineLength, closeTo(Units.feet.toMetres(60), 1e-9));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the reference image gets a Reference row at the bottom of Layers',
    (tester) async {
      final editor = EditorController()..setViewportSize(const Size(800, 600));
      addTearDown(editor.dispose);
      Widget layers() => editorPanel(
        editor: editor,
        builder: (context) => LayersBody(editor: editor),
      );
      await tester.pumpWidget(layers());
      expect(find.textContaining('Reference'), findsNothing);
      editor.addLayer(LayerKind.property);
      editor.addReferenceImage(
        bytes: png,
        mimeType: 'image/png',
        pixelWidth: 400,
        pixelHeight: 200,
      );
      editor.addReferenceImage(
        bytes: Uint8List.fromList(png),
        mimeType: 'image/png',
        pixelWidth: 100,
        pixelHeight: 100,
      );
      editor.selectLayer(editor.document.propertyIds.single);
      await tester.pumpAndSettle();
      // The layer row, then one row per image, top image first.
      final row = find.text('Reference  ·  2');
      expect(row, findsOneWidget);
      final second = find.textContaining('Image 2');
      final first = find.textContaining('Image 1');
      expect(
        tester.getCenter(row).dy,
        greaterThan(tester.getCenter(find.text('Property 1')).dy),
      );
      expect(
        tester.getCenter(second).dy,
        greaterThan(tester.getCenter(row).dy),
      );
      expect(
        tester.getCenter(first).dy,
        greaterThan(tester.getCenter(second).dy),
      );

      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(editor.selectedImage?.id, 'image-1');
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(editor.referenceLayerSelected, isTrue);
      expect(editor.referenceSelected, isFalse);

      await tester.tap(find.bySemanticsLabel('Delete Reference'));
      await tester.pumpAndSettle();
      expect(editor.document.references, isEmpty);
      expect(find.textContaining('Reference'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the image name is renamed in place and removed with the bin', (
    tester,
  ) async {
    final editor = EditorController()..setViewportSize(const Size(800, 600));
    addTearDown(editor.dispose);
    editor.selectTool(Tool.reference);
    editor.addReferenceImage(
      fileName: 'site plan.png',
      bytes: png,
      mimeType: 'image/png',
      pixelWidth: 400,
      pixelHeight: 200,
    );
    await tester.pumpWidget(harness(editor));
    expect(find.text('site plan'), findsOneWidget);
    await tester.tap(find.text('site plan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'North field');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(editor.selectedImage!.displayName, 'North field');
    expect(editor.undoLabel, 'Rename image');
    await tester.tap(find.bySemanticsLabel('Remove North field'));
    await tester.pumpAndSettle();
    expect(editor.document.references, isEmpty);
    expect(find.text('No image selected'), findsOneWidget);
  });
}
