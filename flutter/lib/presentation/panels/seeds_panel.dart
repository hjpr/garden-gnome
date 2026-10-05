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
        final covers = [
          for (final (v, c) in garden.coverVarieties)
            CoverDrag(varietyId: v.id, name: '${v.name} · ${c.name}'),
        ];
        if (all.isEmpty && covers.isEmpty) {
          return const EmptyPanelText('Add seeds in the Seed Vault.');
        }
        final q = _query.trim().toLowerCase();
        final shown = [
          for (final p in all)
            if (q.isEmpty || p.displayName.toLowerCase().contains(q)) p,
        ];
        final shownCovers = [
          for (final c in covers)
            if (q.isEmpty || c.name.toLowerCase().contains(q)) c,
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
            // Cover crops go on Cover beds, not plantings.
            for (final cover in shownCovers)
              _CoverTile(
                key: ValueKey(cover.varietyId),
                editor: widget.editor,
                cover: cover,
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
    final tile = _SeedLabel(
      name: profile.variety.name,
      crop: profile.crop.name,
      trailing: spacing,
    );
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
        message: 'Drag onto a planting',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          borderRadius: BorderRadius.circular(Metrics.radius),
          hoverColor: Palette.hover,
          mouseCursor: SystemMouseCursors.grab,
          onTap: planted == null
              ? () => editor.showNotice('Drag seeds onto a planting')
              : () => plantIn(editor, planted.id, profile),
          child: tile,
        ),
      ),
    );
  }
}

/// One cover crop: drag it onto a Cover bed, or click it to sow the
/// selected Cover bed.
class _CoverTile extends StatelessWidget {
  const _CoverTile({super.key, required this.editor, required this.cover});

  final EditorController editor;
  final CoverDrag cover;

  @override
  Widget build(BuildContext context) {
    final selected = editor.selectedLayerId;
    final bed = selected != null && editor.isCoverBed(selected)
        ? selected
        : null;
    final (variety, crop) = switch (cover.name.split(' · ')) {
      [final v, final c] => (v, c),
      _ => (cover.name, 'Cover crop'),
    };
    final tile = _SeedLabel(
      name: variety,
      crop: crop,
      trailing: 'Cover',
      icon: Icons.grass,
    );
    return Draggable<CoverDrag>(
      data: cover,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 6,
        color: Palette.paper,
        borderRadius: BorderRadius.circular(Metrics.radius),
        child: SizedBox(width: 200, child: tile),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: Tooltip(
        message: 'Drag onto a Cover bed',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          borderRadius: BorderRadius.circular(Metrics.radius),
          hoverColor: Palette.hover,
          mouseCursor: SystemMouseCursors.grab,
          onTap: bed == null
              ? () => editor.showNotice('Drag cover crops onto a Cover bed')
              : () => sowCover(editor, bed, cover),
          child: tile,
        ),
      ),
    );
  }
}

class _SeedLabel extends StatelessWidget {
  const _SeedLabel({
    required this.name,
    required this.crop,
    required this.trailing,
    this.icon = Icons.spa_outlined,
  });

  final String name;
  final String crop;
  final String trailing;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: Row(
      children: [
        Icon(icon, size: 15, color: Palette.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: Palette.ink),
              ),
              Text(
                crop,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Palette.muted),
              ),
            ],
          ),
        ),
        Text(
          trailing,
          style: const TextStyle(fontSize: 11, color: Palette.faint),
        ),
      ],
    ),
  );
}
