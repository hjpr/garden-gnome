import 'editor_controller.dart';
import 'previews.dart';
import 'tools.dart';
import 'transform_box.dart';

/// The selection box to show, or null. Select shows it around a selected
/// shape on an unlocked layer; while a drag is in progress it follows the
/// drawing as it would be if released now.
TransformBox? selectionBoxOf(EditorController editor) {
  final layerId = editor.selectedLayerId;
  if (editor.tool != Tool.select ||
      layerId == null ||
      editor.selection.isEmpty ||
      editor.geometryLockNotice(layerId) != null) {
    return null;
  }
  final preview = editor.preview;
  if (preview is MovePreview) {
    if (preview.box != null) return preview.box;
    if (!preview.document.layers.containsKey(layerId)) return null;
    return TransformBox.around(
      preview.document.geometryOf(layerId),
      editor.selection,
    );
  }
  return TransformBox.around(
    editor.document.geometryOf(layerId),
    editor.selection,
  );
}
