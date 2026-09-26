import 'dart:async';

import 'package:flutter/foundation.dart';

/// What a toast reports, which sets its icon and colours.
enum ToastKind { info, success, error }

/// One short message shown over the editor.
class Toast {
  const Toast._(this.id, this.message, this.kind);

  /// Increases with every toast, so a higher ID is a newer toast.
  final int id;
  final String message;
  final ToastKind kind;
}

/// Short messages that pop up over the editor and go away on their own,
/// in the style of Sonner.
///
/// Kept apart from any one drawing, so a toast raised just before New or
/// Open is still seen afterwards. Pointing at the toasts holds them all
/// (see [pause]), so there is time to read them.
class ToastCenter extends ChangeNotifier {
  /// Older toasts beyond this many are dropped.
  static const int maxKept = 5;

  final List<Toast> _toasts = [];
  final Map<int, Timer> _timers = {};
  bool _paused = false;
  int _nextId = 0;

  /// Oldest first.
  List<Toast> get toasts => List.unmodifiable(_toasts);

  /// How long a toast stays when nothing holds it. Errors stay longer.
  static Duration lifetimeOf(ToastKind kind) => kind == ToastKind.error
      ? const Duration(seconds: 6)
      : const Duration(seconds: 4);

  /// Shows [message]. The same message already showing is brought to the
  /// front and restarted rather than shown twice, so repeated clicks do
  /// not pile up copies.
  void show(String message, {ToastKind kind = ToastKind.info}) {
    for (final old in [..._toasts]) {
      if (old.message == message && old.kind == kind) _remove(old.id);
    }
    final toast = Toast._(_nextId++, message, kind);
    _toasts.add(toast);
    while (_toasts.length > maxKept) {
      _remove(_toasts.first.id);
    }
    if (!_paused) _startTimer(toast);
    notifyListeners();
  }

  void dismiss(int id) {
    if (_remove(id)) notifyListeners();
  }

  /// Holds every toast while the pointer is over them.
  void pause() {
    _paused = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  /// Lets the toasts go again, each with its full time.
  void resume() {
    if (!_paused) return;
    _paused = false;
    _toasts.forEach(_startTimer);
  }

  void _startTimer(Toast toast) {
    _timers[toast.id]?.cancel();
    _timers[toast.id] = Timer(lifetimeOf(toast.kind), () => dismiss(toast.id));
  }

  bool _remove(int id) {
    _timers.remove(id)?.cancel();
    final before = _toasts.length;
    _toasts.removeWhere((t) => t.id == id);
    // The pointer cannot still be over an empty stack.
    if (_toasts.isEmpty) _paused = false;
    return _toasts.length != before;
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
