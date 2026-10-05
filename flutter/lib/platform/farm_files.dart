/// .ggnome files where they live on disk: browser file handles in Chrome
/// and Edge (with a one-time pick in other browsers), paths on desktop.
library;

export 'farm_files_io.dart' if (dart.library.js_interop) 'farm_files_web.dart';
