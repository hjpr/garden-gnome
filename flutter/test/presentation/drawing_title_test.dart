import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/presentation/widgets/drawing_title.dart';

Widget _harness(EditorController editor) => MaterialApp(
  home: Scaffold(
    body: ListenableBuilder(
      listenable: editor,
      builder: (context, _) => Center(
        child: DrawingTitle(
          title: editor.title,
          dirty: editor.isDirty,
          onRename: editor.renameDrawing,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the pencil renames the drawing; Enter keeps it', (tester) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(_harness(editor));
    expect(find.text('Untitled'), findsOneWidget);
    expect(editor.isDirty, isFalse);

    await tester.tap(find.byTooltip('Rename drawing'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Back yard');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(editor.title, 'Back yard');
    expect(find.text('Back yard'), findsOneWidget);
    expect(editor.isDirty, isTrue, reason: 'the new name is not saved yet');
    editor.markSaved(editor.document);
    expect(editor.isDirty, isFalse);
  });

  testWidgets('Esc keeps the old name; a blank name is ignored', (
    tester,
  ) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(_harness(editor));

    await tester.tap(find.byTooltip('Rename drawing'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Front yard');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(editor.title, 'Untitled');
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byTooltip('Rename drawing'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(editor.title, 'Untitled');
  });
}
