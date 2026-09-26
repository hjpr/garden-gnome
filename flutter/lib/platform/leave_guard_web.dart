import 'dart:js_interop';

import 'package:web/web.dart' as web;

JSFunction? _listener;

void setLeaveWarning(bool enabled) {
  if (enabled && _listener == null) {
    _listener = ((web.Event event) => event.preventDefault()).toJS;
    web.window.addEventListener('beforeunload', _listener);
  } else if (!enabled && _listener != null) {
    web.window.removeEventListener('beforeunload', _listener);
    _listener = null;
  }
}
