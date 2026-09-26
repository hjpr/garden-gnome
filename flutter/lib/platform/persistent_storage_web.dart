import 'package:web/web.dart' as web;

bool _asked = false;

void requestPersistentStorage() {
  if (_asked) return;
  _asked = true;
  try {
    // The answer is not needed: denial only means the browser may clear
    // storage under pressure, which the save messages already warn about.
    web.window.navigator.storage.persist();
  } catch (_) {
    // Older browsers have no StorageManager.
  }
}
