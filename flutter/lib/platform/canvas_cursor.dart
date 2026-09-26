/// Shows the Select tool's own arrow as the mouse cursor over the canvas.
///
/// Flutter can only pick the browser's built-in cursors, so on the web the
/// arrow from select.svg is set as a CSS cursor on the app's element. Other
/// platforms fall back to the system arrow and this does nothing.
library;

export 'canvas_cursor_stub.dart'
    if (dart.library.js_interop) 'canvas_cursor_web.dart';
