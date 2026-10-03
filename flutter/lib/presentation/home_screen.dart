import 'package:flutter/material.dart';

import '../application/app_tools.dart';
import '../application/garden_controller.dart';
import '../domain/grow/planting.dart';
import '../domain/grow/planting_windows.dart';
import 'tool_switcher.dart';
import 'theme.dart';

/// The home view: one card per tool, in the order the season runs, each
/// with a live count so the gardener sees at a glance where work is due.
class HomeBody extends StatelessWidget {
  const HomeBody({super.key, required this.navigator, required this.garden});

  final AppNavigator navigator;
  final GardenController garden;

  String _summary(AppTool tool) {
    switch (tool) {
      case AppTool.build:
        return 'Land, beds and plantings';
      case AppTool.seedVault:
        final n = garden.record.varieties.length;
        return n == 1 ? '1 variety' : '$n varieties';
      case AppTool.greenhouse:
        final n = garden.inGreenhouse().length;
        return n == 0 ? 'Nothing growing' : '$n growing';
      case AppTool.grow:
        final open = garden
            .recommendations()
            .where(
              (r) => r.timing.isOpen && r.window.kind != WindowKind.plantOut,
            )
            .length;
        return open == 0 ? 'Nothing to sow now' : '$open to sow now';
      case AppTool.harvest:
        final today = garden.today;
        final n = garden
            .schedules(PlantingStage.inGround)
            .where((s) => s.harvest.contains(today))
            .length;
        return n == 0 ? 'Nothing to pick now' : '$n picking now';
    }
  }

  static const _about = {
    AppTool.build: 'Draw your farm: land, beds and plantings.',
    AppTool.seedVault: 'The seed you have and how to grow it.',
    AppTool.greenhouse: 'Trays growing and when they go out.',
    AppTool.grow: 'What to sow in the next two months.',
    AppTool.harvest: 'When each crop comes ready.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.chrome,
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.eco, size: 36, color: Palette.accent),
            const SizedBox(height: 6),
            const Text(
              'Garden Gnome',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              garden.farm.farmName,
              key: const ValueKey('farm-name'),
              style: const TextStyle(fontSize: 14, color: Palette.muted),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: [
                for (final tool in AppTool.values)
                  _ToolCard(
                    tool: tool,
                    about: _about[tool]!,
                    summary: _summary(tool),
                    onOpen: () => navigator.open(tool),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.tool,
    required this.about,
    required this.summary,
    required this.onOpen,
  });

  final AppTool tool;
  final String about;
  final String summary;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 196,
    height: 190,
    child: Material(
      color: Palette.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Palette.panelBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        hoverColor: Palette.hover,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Palette.wash,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: toolIcon(tool, size: 22)),
              ),
              const SizedBox(height: 12),
              Text(
                tool.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                about,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Palette.muted),
              ),
              const Spacer(),
              Text(
                summary.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sectionTitleStyle.copyWith(color: Palette.accent),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
