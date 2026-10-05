/// Where installed textures are kept: IndexedDB in the browser, a
/// database file in the app's data folder on desktop.
library;

export 'texture_storage_io.dart'
    if (dart.library.js_interop) 'texture_storage_web.dart';
