import 'package:flutter/material.dart';

import '../application/app_tools.dart';
import '../application/garden_controller.dart';
import 'tool_switcher.dart';
import 'theme.dart';

/// The Pocket Garden illustration (docs/concepts/whimsy). Decoration only:
/// nothing in it is clickable, and Home works the same if it fails to load.
const homeIllustration = 'assets/home/pocket_garden.jpg';

/// The home view: the same white header as every tool, a painted garden
/// banner, and one card per tool in the order the season runs, each with a
/// live count so the gardener sees at a glance where work is due.
class HomeBody extends StatelessWidget {
  const HomeBody({super.key, required this.navigator, required this.garden});

  final AppNavigator navigator;
  final GardenController garden;

  String _summary(AppTool tool) {
    switch (tool) {
      case AppTool.plan:
        return 'Land, beds and plantings';
      case AppTool.seedVault:
        final n = garden.record.varieties.length;
        return n == 1 ? '1 variety' : '$n varieties';
      case AppTool.grow:
        final growing =
            garden.inGround().length +
            garden.inGreenhouse().length +
            garden.coverBeds().length;
        // Sowing is only offered for what is planned on the map.
        final toSow = garden.plannedSowings().length;
        return [
          growing == 0 ? 'Nothing growing' : '$growing growing',
          if (toSow > 0) '$toSow to sow',
        ].join(' · ');
    }
  }

  static const _about = {
    AppTool.seedVault: 'Start here: the seed you have and how to grow it.',
    AppTool.plan: 'Draw your farm, then drag your seed onto it.',
    AppTool.grow: 'Sow in place, or start trays to transplant.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.chrome,
    body: Column(
      children: [
        _HomeHeader(navigator: navigator),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              child: ConstrainedBox(
                // Fill the window so the block can sit a little above
                // centre instead of hanging from the header.
                constraints: BoxConstraints(minHeight: box.maxHeight - 52),
                child: Align(
                  alignment: const Alignment(0, -0.2),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _GardenBanner(farmName: garden.farm.farmName),
                        // Cards ride up over the banner's faded foot, so the
                        // garden reads as the ground the tools stand on.
                        Transform.translate(
                          offset: const Offset(0, -_cardOverlap),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _ToolRow(
                              stacked: box.maxWidth < 1000,
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
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

const _cardOverlap = 56.0;

/// Same bar as the growing tools' header, so Home and the tools share one
/// frame; the switcher reads "Garden Gnome" here.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.navigator});

  final AppNavigator navigator;

  @override
  Widget build(BuildContext context) => Container(
    height: Metrics.headerHeight,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: const BoxDecoration(
      color: Palette.paper,
      border: Border(bottom: BorderSide(color: Palette.panelBorder)),
    ),
    child: Row(children: [ToolSwitcher(navigator: navigator)]),
  );
}

/// The painted garden in a rounded frame, fading into the window colour at
/// its foot. The farm name sits on it as a plain native chip.
class _GardenBanner extends StatelessWidget {
  const _GardenBanner({required this.farmName});

  final String farmName;

  // The crop's own proportions (1376 × 436), so the picture is never cut.
  static const _aspect = 1376 / 436;

  // Only the top is rounded: the foot fades into the window colour, so it
  // has no edge to show beside the cards.
  static const _corners = BorderRadius.vertical(top: Radius.circular(12));

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: _aspect,
    child: ClipRRect(
      borderRadius: _corners,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The picture itself fades out (rather than a colour laid over
          // it), so its foot has no edge against the window.
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.6, 1],
              colors: [Colors.white, Color(0x00FFFFFF)],
            ).createShader(rect),
            child: Image.asset(
              homeIllustration,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              // Missing art leaves just the farm chip on the window colour.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          Positioned(left: 16, top: 16, child: _FarmChip(name: farmName)),
        ],
      ),
    ),
  );
}

class _FarmChip extends StatelessWidget {
  const _FarmChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
    decoration: BoxDecoration(
      color: Palette.paper.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Palette.panelBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.eco, size: 16, color: Palette.accent),
        const SizedBox(width: 6),
        Text(
          name,
          key: const ValueKey('farm-name'),
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

/// Three equal cards side by side (under the cabinet, the plan table and
/// the greenhouse in the picture), or stacked in a narrow window.
class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.stacked, required this.children});

  final bool stacked;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (stacked) {
      return Column(
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            // Gives the card a bounded height for its bottom-pinned count.
            IntrinsicHeight(child: c),
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: c),
          ],
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) => DecoratedBox(
    // A soft lift so the cards read as standing on the garden.
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
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
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          child: Row(
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
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      about,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Palette.muted,
                      ),
                    ),
                    // The count lines up across cards whatever the
                    // length of the line above it.
                    const Spacer(),
                    const SizedBox(height: 12),
                    Text(
                      summary.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sectionTitleStyle.copyWith(color: Palette.accent),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Palette.faint),
            ],
          ),
        ),
      ),
    ),
  );
}
