/// Asks the browser to keep this site's saved drawings even when disk
/// space runs low. The browser may say no; saving works either way.
/// On other platforms this does nothing.
library;

export 'persistent_storage_stub.dart'
    if (dart.library.js_interop) 'persistent_storage_web.dart';
