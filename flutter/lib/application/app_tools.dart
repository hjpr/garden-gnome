import 'package:flutter/foundation.dart';

/// The app's tools, in the order the gardener meets them: record the seed,
/// lay out the land and place the seed, then grow it.
enum AppTool {
  seedVault('Seed Vault'),
  plan('Plan'),
  grow('Grow');

  const AppTool(this.label);

  final String label;
}

/// Grow's two halves, switched in its header like Plan's Build | Plant:
/// sowing in place, and seed started in the greenhouse to transplant.
enum GrowMode {
  sow('Sow'),
  transplant('Transplant');

  const GrowMode(this.label);

  final String label;
}

/// Which tool is open. Null is the home view that lists them all.
class AppNavigator extends ChangeNotifier {
  AppNavigator([this._current]);

  AppTool? _current;
  AppTool? get current => _current;

  /// Kept while other tools are open, so Grow comes back as it was left.
  GrowMode get growMode => _growMode;
  GrowMode _growMode = GrowMode.sow;

  set growMode(GrowMode mode) {
    if (mode == _growMode) return;
    _growMode = mode;
    notifyListeners();
  }

  void open(AppTool? tool) {
    if (tool == _current) return;
    _current = tool;
    notifyListeners();
  }

  void home() => open(null);
}
