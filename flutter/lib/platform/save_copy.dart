/// Saves bytes as a file the user keeps: a download in the browser, the
/// system save dialog on desktop. Returns false when the user cancels.
library;

export 'save_copy_io.dart' if (dart.library.js_interop) 'save_copy_web.dart';
