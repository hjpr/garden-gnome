import 'package:flutter/material.dart';

import '../../application/app_tools.dart';
import '../../application/toasts.dart';
import '../../application/workspace_settings.dart';
import '../theme.dart';
import '../widgets/toaster.dart';
import '../tool_switcher.dart';

/// The frame every growing tool sits in: the shared header with the tool
/// switcher, the tool's body, and toasts on top.
class GardenPage extends StatelessWidget {
  const GardenPage({
    super.key,
    required this.navigator,
    required this.toasts,
    required this.body,
    this.actions = const [],
  });

  final AppNavigator navigator;
  final ToastCenter toasts;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.chrome,
    body: Stack(
      children: [
        Column(
          children: [
            _GardenHeader(navigator: navigator, actions: actions),
            Expanded(child: body),
          ],
        ),
        Positioned.fill(
          child: Toaster(toasts: toasts, position: ToastPosition.bottom),
        ),
      ],
    ),
  );
}

class _GardenHeader extends StatelessWidget {
  const _GardenHeader({required this.navigator, this.actions = const []});

  final AppNavigator navigator;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    height: Metrics.headerHeight,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: const BoxDecoration(
      color: Palette.paper,
      border: Border(bottom: BorderSide(color: Palette.panelBorder)),
    ),
    child: Row(
      children: [
        ToolSwitcher(navigator: navigator),
        const Spacer(),
        ...actions,
      ],
    ),
  );
}
