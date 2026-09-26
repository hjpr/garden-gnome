/// Sets the mouse cursor over the canvas: the Select tool's own arrow,
/// the selection box's scale arrows, and its rotate arrow.
///
/// Flutter can only pick the browser's built-in cursors and has no rotate
/// cursor, so on the web the cursor is set in CSS on the app's element.
/// Other platforms do nothing and keep the system cursor.
library;

export 'canvas_cursor_kind.dart';
export 'canvas_cursor_stub.dart'
    if (dart.library.js_interop) 'canvas_cursor_web.dart';
