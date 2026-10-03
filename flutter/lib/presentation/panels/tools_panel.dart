import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../application/tools.dart';
import '../theme.dart';
import '../widgets/button_grid.dart';
import '../widgets/icon_controls.dart';
import '../widgets/property_controls.dart';

/// The drawing tools as a grid of buttons, then the chosen tool's functions.
class ToolsBody extends StatelessWidget {
  const ToolsBody({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ButtonGrid(
          children: [
            for (final tool in Tool.values.where(
              (tool) => tool.availableIn(editor.mode),
            ))
              _ToolButton(
                icon: tool.icon,
                label: tool.label,
                selected: editor.tool == tool,
                // The Select arrow stays black, as in most drawing programs.
                iconColor: tool == Tool.select ? Colors.black : null,
                onTap: () => editor.selectTool(tool),
              ),
          ],
        ),
        if (editor.mode == EditMode.plant)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Select plantings to plant seeds. Edit geometry in Build mode.',
              style: TextStyle(fontSize: 12, color: Palette.muted),
            ),
          ),
        if (editor.mode == EditMode.build && editor.tool.hasFunctionChoice)
          PropertyGroup(
            title: '${editor.tool.label} functions'.toUpperCase(),
            children: [
              ButtonGrid(
                children: [
                  for (final function in editor.tool.functions)
                    _ToolButton(
                      // A new tool's buttons start fresh rather than
                      // animating from the old tool's button in that slot.
                      key: ValueKey(function),
                      icon: function.icon,
                      label: function.label,
                      selected: editor.function == function,
                      onTap: () => editor.selectFunction(function),
                    ),
                ],
              ),
              if (editor.function == ToolFunction.regularPolygon)
                PropertyRow(
                  label: 'Sides',
                  child: _SidesStepper(editor: editor),
                ),
            ],
          ),
      ],
    );
  }
}

/// Minus and plus buttons around the number of sides for Polygon → Regular.
class _SidesStepper extends StatelessWidget {
  const _SidesStepper({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final sides = editor.polygonSides;
    return Row(
      children: [
        IconAction(
          iconData: Icons.remove,
          label: 'Fewer sides',
          onPressed: sides > EditorController.minPolygonSides
              ? () => editor.setPolygonSides(sides - 1)
              : null,
        ),
        Expanded(
          child: Text(
            '$sides',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Palette.ink),
          ),
        ),
        IconAction(
          iconData: Icons.add,
          label: 'More sides',
          onPressed: sides < EditorController.maxPolygonSides
              ? () => editor.setPolygonSides(sides + 1)
              : null,
        ),
      ],
    );
  }
}

/// An icon over a short label; raised on white when chosen.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconColor,
  });

  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colour = selected ? Palette.accent : Palette.ink;
    return Semantics(
      button: true,
      selected: selected,
      enabled: true,
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          // Fade to see-through WHITE: Colors.transparent is see-through
          // black, and the fade between it and white passes through grey.
          color: selected ? Palette.paper : Palette.paper.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(Metrics.radius),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Metrics.radius),
            // A selected button hovers in its own white, never in
            // Colors.transparent: that is transparent BLACK, and a hover
            // already showing when the button is clicked keeps its
            // opacity and turns solid black.
            hoverColor: selected ? Palette.paper : Palette.hover,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                children: [
                  AppIcon(icon, size: 18, color: iconColor ?? colour),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: colour,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
