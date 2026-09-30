import 'package:flutter/material.dart';

import '../application/app_tools.dart';
import 'theme.dart';
import 'widgets/icon_controls.dart';

/// The picture for each tool, used on the home view and in the switcher.
Widget toolIcon(AppTool? tool, {double size = 18, Color? color}) {
  final c = color ?? Palette.accent;
  return switch (tool) {
    null => Icon(Icons.eco, size: size, color: c),
    AppTool.build => Icon(Icons.architecture, size: size, color: c),
    AppTool.seedVault => Icon(Icons.inventory_2_outlined, size: size, color: c),
    AppTool.greenhouse => AppIcon('greenhouse.svg', size: size, color: c),
    AppTool.grow => Icon(Icons.calendar_month_outlined, size: size, color: c),
    AppTool.harvest => Icon(Icons.agriculture_outlined, size: size, color: c),
  };
}

/// The leaf at the left of every header: shows the open tool's name and
/// opens a menu to go home or to any other tool.
class ToolSwitcher extends StatelessWidget {
  const ToolSwitcher({super.key, required this.navigator});

  final AppNavigator navigator;

  @override
  Widget build(BuildContext context) {
    final current = navigator.current;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: toolIcon(null, size: 16),
          onPressed: navigator.home,
          child: const Text('Home'),
        ),
        const Divider(),
        for (final tool in AppTool.values)
          MenuItemButton(
            leadingIcon: toolIcon(
              tool,
              size: 16,
              color: tool == current ? Palette.accent : Palette.muted,
            ),
            trailingIcon: tool == current
                ? const Icon(Icons.check, size: 16, color: Palette.accent)
                : null,
            onPressed: () => navigator.open(tool),
            child: Text(tool.label),
          ),
      ],
      builder: (context, menu, _) => Tooltip(
        message: 'Switch tool',
        child: InkWell(
          borderRadius: BorderRadius.circular(Metrics.radius),
          hoverColor: Palette.hover,
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.eco, size: 20, color: Palette.accent),
                const SizedBox(width: 6),
                Text(
                  current?.label ?? 'Garden Gnome',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(Icons.expand_more, size: 16, color: Palette.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
