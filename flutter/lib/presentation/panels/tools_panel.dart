import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../application/tools.dart';
import '../theme.dart';
import '../widgets/panel.dart';

/// The drawing tools as a grid of buttons, then the chosen tool's functions.
class ToolsBody extends StatelessWidget {
  const ToolsBody({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ButtonGrid(
          children: [
            for (final tool in Tool.values)
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
        if (editor.tool.hasFunctionChoice)
          PropertyGroup(
            title: '${editor.tool.label} functions'.toUpperCase(),
            children: [
              _ButtonGrid(
                children: [
                  for (final function in editor.tool.functions)
                    _ToolButton(
                      icon: _functionIcon(editor.tool, function),
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

  static String _functionIcon(Tool tool, ToolFunction function) =>
      tool == Tool.line && function == ToolFunction.delete
      ? 'point-delete.svg'
      : function.icon;
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

/// Buttons in a light tray, [columns] to a row. Further buttons wrap onto
/// new rows; every button keeps the same width, so a short last row lines
/// up with the rows above.
class _ButtonGrid extends StatelessWidget {
  const _ButtonGrid({required this.children});

  static const columns = 3;
  static const _gap = 3.0;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Palette.field,
      borderRadius: BorderRadius.circular(Metrics.radius + 2),
    ),
    child: Column(
      children: [
        for (var start = 0; start < children.length; start += columns) ...[
          if (start > 0) const SizedBox(height: _gap),
          Row(
            children: [
              for (var i = start; i < start + columns; i++) ...[
                if (i > start) const SizedBox(width: _gap),
                Expanded(
                  child: i < children.length ? children[i] : const SizedBox(),
                ),
              ],
            ],
          ),
        ],
      ],
    ),
  );
}

/// An icon over a short label; raised on white when chosen.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
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
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: selected ? Palette.paper : Colors.transparent,
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
            hoverColor: selected ? Colors.transparent : Palette.hover,
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
