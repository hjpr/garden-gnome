import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/toasts.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/presentation/panels/layers_panel.dart';
import 'package:garden_gnome/presentation/panels/preferences_panel.dart';
import 'package:garden_gnome/presentation/panels/properties_panel.dart';
import 'package:garden_gnome/presentation/widgets/toaster.dart';

void main() {
  group('ToastCenter', () {
    // testWidgets runs on fake time, so tester.pump moves the clock.
    testWidgets('toasts leave on their own; errors stay longer', (
      tester,
    ) async {
      final toasts = ToastCenter();
      addTearDown(toasts.dispose);
      toasts.show('Saved');
      toasts.show('Broken', kind: ToastKind.error);
      await tester.pump(const Duration(seconds: 5));
      expect(toasts.toasts.map((t) => t.message), ['Broken']);
      await tester.pump(const Duration(seconds: 2));
      expect(toasts.toasts, isEmpty);
    });

    testWidgets('pointing at the toasts holds them until the pointer leaves', (
      tester,
    ) async {
      final toasts = ToastCenter()..show('Saved');
      addTearDown(toasts.dispose);
      toasts.pause();
      await tester.pump(const Duration(seconds: 30));
      expect(toasts.toasts, hasLength(1));
      toasts.resume();
      await tester.pump(const Duration(seconds: 5));
      expect(toasts.toasts, isEmpty);
    });

    test('a repeated message is shown once, and only a few are kept', () {
      final toasts = ToastCenter();
      addTearDown(toasts.dispose);
      toasts
        ..show('Same')
        ..show('Same');
      expect(toasts.toasts, hasLength(1));
      for (var i = 0; i < 10; i++) {
        toasts.show('Toast $i');
      }
      expect(toasts.toasts, hasLength(ToastCenter.maxKept));
      expect(toasts.toasts.last.message, 'Toast 9');
    });
  });

  test('drawing with no layers raises an error toast', () {
    final editor = EditorController();
    addTearDown(editor.dispose);
    final input = CanvasInput(editor);
    editor.selectTool(Tool.point);
    input
      ..hover(const Offset(100, 100))
      ..press(const Offset(100, 100), shift: false)
      ..release(const Offset(100, 100));
    final toast = editor.toasts.toasts.single;
    expect(toast.message, 'Add a Field layer to start drawing.');
    expect(toast.kind, ToastKind.error);
    expect(editor.document.layers, isEmpty);
  });

  testWidgets('empty Properties and Layers say so in grey', (tester) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PropertiesBody(editor: editor),
              LayersBody(editor: editor),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Nothing selected.'), findsOneWidget);
    expect(find.text('Add a field to start.'), findsOneWidget);
  });

  testWidgets('the toaster sits at the chosen edge with an error icon', (
    tester,
  ) async {
    final toasts = ToastCenter();
    addTearDown(toasts.dispose);
    Future<void> pump(ToastPosition position) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Toaster(toasts: toasts, position: position),
        ),
      ),
    );
    await pump(ToastPosition.bottom);
    toasts.show('Add a Field layer to start drawing.', kind: ToastKind.error);
    await tester.pumpAndSettle();
    final text = find.text('Add a Field layer to start drawing.');
    expect(text, findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
    final screen = tester.getSize(find.byType(Scaffold));
    expect(tester.getCenter(text).dy, greaterThan(screen.height / 2));

    await pump(ToastPosition.top);
    await tester.pumpAndSettle();
    expect(tester.getCenter(text).dy, lessThan(screen.height / 2));

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(text, findsNothing);
  });

  testWidgets('Preferences lists categories; Notifications sets the edge', (
    tester,
  ) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 360,
            child: ListenableBuilder(
              listenable: editor,
              builder: (context, _) => PreferencesBody(editor: editor),
            ),
          ),
        ),
      ),
    );
    for (final label in ['Canvas', 'Style', 'Notifications']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Minimum (%)'), findsOneWidget);
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
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 360,
            child: PreferencesBody(editor: editor),
          ),
        ),
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
}
