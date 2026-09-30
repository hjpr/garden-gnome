import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/presentation/panels/preferences_panel.dart';
import 'package:garden_gnome/presentation/widgets/property_controls.dart';

import '../support/widget_harness.dart';

void main() {
  testWidgets('Preferences lists categories; Notifications sets the edge', (
    tester,
  ) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      editorPanel(
        editor: editor,
        width: 600,
        height: 360,
        scrollable: false,
        builder: (context) => PreferencesBody(editor: editor),
      ),
    );
    for (final label in ['Canvas', 'Style', 'Notifications']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Lowest (ft)'), findsOneWidget);
    expect(find.text('Menu size'), findsOneWidget);
    expect(find.text('Line width (px)'), findsNothing);

    await tester.tap(find.text('Style'));
    await tester.pumpAndSettle();
    expect(find.text('Line width (px)'), findsOneWidget);
    expect(find.text('Color'), findsOneWidget);

    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bottom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top').last);
    await tester.pumpAndSettle();
    expect(editor.settings.appearance.toastPosition, ToastPosition.top);
  });

  testWidgets('a value typed in one category is applied from another', (
    tester,
  ) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      editorPanel(
        editor: editor,
        width: 600,
        height: 360,
        scrollable: false,
        builder: (context) => PreferencesBody(editor: editor),
      ),
    );
    await tester.tap(find.text('Style'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '4');
    await tester.tap(find.text('Canvas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(editor.settings.appearance.lineWidth, 4);
  });

  testWidgets('camera heights are typed in the drawing\'s units', (
    tester,
  ) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      editorPanel(
        editor: editor,
        width: 600,
        height: 360,
        scrollable: false,
        builder: (context) => PreferencesBody(editor: editor),
      ),
    );
    Finder box(String label) => find.descendant(
      of: find.widgetWithText(PropertyRow, label),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(box('Lowest (ft)')).controller!.text, '5');
    expect(
      tester.widget<TextField>(box('Highest (ft)')).controller!.text,
      '500',
    );
    await tester.enterText(box('Lowest (ft)'), '2');
    await tester.enterText(box('Highest (ft)'), '2000');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final limits = editor.settings.appearance.heightLimits;
    expect(limits.lowest, closeTo(2 * 0.3048, 1e-9));
    expect(limits.highest, closeTo(2000 * 0.3048, 1e-9));
  });
}
