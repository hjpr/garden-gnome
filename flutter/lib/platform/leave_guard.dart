/// Asks the browser to warn before the tab is closed or reloaded.
///
/// Browsers show only their own generic message, and only after the user
/// has interacted with the page. On other platforms this does nothing.
library;

export 'leave_guard_stub.dart'
    if (dart.library.js_interop) 'leave_guard_web.dart';
