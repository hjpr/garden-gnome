/// Opens a web page outside the app: a new browser tab on web, the
/// system browser on desktop. Returns false when it could not.
library;

export 'open_link_io.dart' if (dart.library.js_interop) 'open_link_web.dart';
