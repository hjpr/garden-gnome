import 'editor_controller.dart';
import 'tools.dart';

/// A one-line hint for the status bar describing what a click will do now.
/// Select has none: its part of the status bar shows the selection's size
/// instead.
String toolPrompt(EditorController editor) {
  if (editor.tool == Tool.select) return '';
  if (editor.tool == Tool.reference) return _referencePrompt(editor);
  if (editor.selectedLayer == null) {
    return editor.document.fields.isEmpty
        ? 'Add a field in Layers to start drawing'
        : 'Select a layer in Layers to draw on it';
  }

  final locked = editor.lockNotice(editor.selectedLayerId!);
  if (locked != null) return locked;

  return switch ((editor.tool, editor.function)) {
    (Tool.point, ToolFunction.place) =>
      'Click to place a point. Click on a line to split it',
    (Tool.point, ToolFunction.delete) =>
      'Click a point to delete it with its lines',
    (Tool.line, ToolFunction.draw) when editor.lineAnchor == null =>
      'Click to start a line, or click an open end point to continue one',
    (Tool.line, ToolFunction.draw) =>
      'Click the next corner. Click a ringed point to join it. Enter or Esc to finish',
    (Tool.arc, _) when editor.arcPoints.isEmpty =>
      'Click the start of the Arc. Open end points can be reused',
    (Tool.arc, _) when editor.arcPoints.length == 1 =>
      'Click a point the Arc passes through. Esc to cancel',
    (Tool.arc, _) => 'Click the end of the Arc. Esc to cancel',
    (Tool.polygon, ToolFunction.regularPolygon)
        when editor.polygonStart == null =>
      'Click the center of the ${editor.polygonSides}-sided polygon',
    (Tool.polygon, ToolFunction.regularPolygon) =>
      'Click to place a corner. Esc to cancel',
    (Tool.polygon, ToolFunction.rectangle) when editor.polygonStart == null =>
      'Click one corner of the rectangle',
    (Tool.polygon, ToolFunction.rectangle) =>
      'Click the opposite corner. Esc to cancel',
    (Tool.line, ToolFunction.join) when editor.joinStart == null =>
      'Click the first of two points to join',
    (Tool.line, ToolFunction.join) =>
      'Click the next point to join. Esc to finish',
    (Tool.circle, ToolFunction.centerCircle) when editor.circleStart == null =>
      'Click the center of the circle, or a ringed point to use it',
    (Tool.circle, ToolFunction.centerCircle) =>
      'Click to set the size. Esc to cancel',
    (Tool.circle, ToolFunction.twoPointCircle)
        when editor.circleStart == null =>
      'Click one side of the circle',
    (Tool.circle, ToolFunction.twoPointCircle) =>
      'Click the opposite side. Esc to cancel',
    (Tool.pattern, _)
        when editor.document.geometryOf(editor.selectedLayerId!).region ==
            null =>
      'Close a shape before adding a pattern',
    (Tool.pattern, ToolFunction.noPattern) =>
      'Click inside a shape to remove the layer\'s pattern',
    (Tool.pattern, final function) =>
      'Click inside a shape to fill the layer with ${function.label}',
    (Tool.line, ToolFunction.delete) =>
      'Click a line to delete it. Its points stay',
    _ => '',
  };
}

String _referencePrompt(EditorController editor) {
  final blocker = editor.referenceBlocker;
  if (blocker != null) return blocker;
  if (editor.referenceLineStart != null) {
    return 'Click the other end on the same image. Esc to cancel';
  }
  final image = editor.selectedImage;
  if (image != null && image.hasLine && !image.isCalibrated) {
    return 'Enter the line\'s real length in Properties, or click to draw a new line';
  }
  return 'Click one end of a distance you know on a reference image';
}
