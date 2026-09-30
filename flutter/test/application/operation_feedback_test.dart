import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/alignment.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/previews.dart';
import 'package:garden_gnome/domain/vec.dart';

void main() {
  late EditorController editor;
  setUp(() => editor = EditorController());
  tearDown(() => editor.dispose());

  test('a refused Align hover owns and clears its notice', () {
    editor.previewAlign(AlignEdge.left);
    expect(editor.notice, contains('Select two'));
    editor.previewAlign(null);
    expect(editor.preview, isNull);
    expect(editor.notice, isNull);
  });

  test('an old Align exit cannot clear a newer Boolean hover', () {
    editor.previewAlign(AlignEdge.left);
    const preview = BooleanPreview(
      layerId: 'layer',
      operandId: 'shape',
      valid: false,
      problem: 'Boolean refusal',
    );
    editor.setPreview(preview);
    editor.previewAlign(null);
    expect(editor.preview, same(preview));
    expect(editor.notice, 'Boolean refusal');
    editor.previewBoolean(null);
    expect(editor.notice, isNull);
  });

  test('an old Boolean exit cannot clear a newer Align hover', () {
    editor.previewAlign(AlignEdge.left);
    final preview = editor.preview;
    editor.previewBoolean(null);
    expect(editor.preview, same(preview));
    expect(editor.notice, contains('Select two'));
  });

  test('replacing a refused preview clears its notice and notifies the UI', () {
    editor.previewAlign(AlignEdge.left);
    var updates = 0;
    editor.addListener(() => updates++);
    const next = PointPreview(Vec(1, 2), valid: true);
    editor.setPreview(next);
    expect(editor.notice, isNull);
    expect(updates, 1);
    editor.previewAlign(null);
    expect(editor.preview, same(next));
  });

  test('leaving an old operation does not erase a command refusal', () {
    editor.previewAlign(AlignEdge.left);
    editor.showNotice('New refusal');
    editor.previewAlign(null);
    expect(editor.notice, 'New refusal');
  });
}
