import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/toasts.dart';
import 'package:garden_gnome/application/tools.dart';

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
    expect(toast.message, 'Add a Property layer to start drawing.');
    expect(toast.kind, ToastKind.error);
    expect(editor.document.layers, isEmpty);
  });
}
