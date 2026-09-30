import 'package:flutter/foundation.dart';

/// The app's tools, in the order the gardener meets them: lay out the
/// land, record seed, start seed, plan sowing, pick.
enum AppTool {
  build('Build'),
  seedVault('Seed Vault'),
  greenhouse('Greenhouse'),
  grow('Grow'),
  harvest('Harvest');

  const AppTool(this.label);

  final String label;
}

/// Which tool is open. Null is the home view that lists them all.
class AppNavigator extends ChangeNotifier {
  AppNavigator([this._current]);

  AppTool? _current;
  AppTool? get current => _current;

  void open(AppTool? tool) {
    if (tool == _current) return;
    _current = tool;
    notifyListeners();
  }

  void home() => open(null);
}
