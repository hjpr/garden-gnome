/// Where the browser drawing library keeps farms: IndexedDB in the
/// browser. Desktop saves to files instead, so it gets an empty memory
/// store that nothing is written to.
library;

export 'browser_storage_stub.dart'
    if (dart.library.js_interop) 'browser_storage_web.dart';
