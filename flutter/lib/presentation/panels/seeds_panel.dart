import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../application/garden_controller.dart';
import '../../application/planting.dart';
import '../../domain/grow/variety.dart';
import '../theme.dart';
import '../widgets/panel.dart';

/// Plant mode's seed list: every Seed Vault variety, dragged onto a grow
/// zone on the canvas to plant it there. Clicking one plants it in the
/// selected grow zone.
class SeedsBody extends StatefulWidget {
  const SeedsBody({super.key, required this.editor, required this.garden});

  final EditorController editor;
  final GardenController? garden;

  @override
  State<SeedsBody> createState() => _SeedsBodyState();
}

class _SeedsBodyState extends State<SeedsBody> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final garden = widget.garden;
    if (garden == null) return const EmptyPanelText('No Seed Vault.');
    return ListenableBuilder(
      listenable: garden,
      builder: (context, _) {
        final all = garden.profiles;
        if (all.isEmpty) {
          return const EmptyPanelText('Add seeds in the Seed Vault.');
        }
        final q = _query.trim().toLowerCase();
        final shown = [
          for (final p in all)
            if (q.isEmpty || p.displayName.toLowerCase().contains(q)) p,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 30,
              child: TextField(
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                  hintText: 'Search seeds',
                  prefixIcon: Icon(Icons.search, size: 16),
                  prefixIconConstraints: BoxConstraints(minWidth: 28),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 4),
            for (final profile in shown)
              _SeedTile(
                key: ValueKey(profile.id),
                editor: widget.editor,
                profile: profile,
              ),
          ],
        );
      },
    );
  }
}

/// One variety: drag it onto a grow zone, or click it to plant the
/// selected grow zone.
class _SeedTile extends StatelessWidget {
  const _SeedTile({super.key, required this.editor, required this.profile});

  final EditorController editor;
  final VarietyProfile profile;

  @override
  Widget build(BuildContext context) {
    final spacing =
        '${profile.inRowSpacingIn.min}″ × ${profile.betweenRowSpacingIn.min}″';
    final selected = editor.selectedLayerId;
    final planted = selected != null && editor.isGrowZone(selected)
        ? editor.document.layers[selected]
        : null;
    final tile = _SeedLabel(profile: profile, spacing: spacing);
    return Draggable<VarietyProfile>(
      data: profile,
      // The drop lands where the pointer is, not the card's corner.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 6,
        color: Palette.paper,
        borderRadius: BorderRadius.circular(Metrics.radius),
        child: SizedBox(width: 200, child: tile),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: Tooltip(
        message: 'Drag onto a grow zone',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          borderRadius: BorderRadius.circular(Metrics.radius),
          hoverColor: Palette.hover,
          mouseCursor: SystemMouseCursors.grab,
          onTap: planted == null
              ? () => editor.showNotice('Drag seeds onto a grow zone')
              : () => plantIn(editor, planted.id, profile),
          child: tile,
        ),
      ),
    );
  }
}

class _SeedLabel extends StatelessWidget {
  const _SeedLabel({required this.profile, required this.spacing});

  final VarietyProfile profile;
  final String spacing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: Row(
      children: [
        const Icon(Icons.spa_outlined, size: 15, color: Palette.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.variety.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: Palette.ink),
              ),
              Text(
                profile.crop.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Palette.muted),
              ),
            ],
          ),
        ),
        Text(
          spacing,
          style: const TextStyle(fontSize: 11, color: Palette.faint),
        ),
      ],
    ),
  );
}
