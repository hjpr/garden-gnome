import 'package:flutter/material.dart';

import '../application/editor_controller.dart';
import '../application/tool_prompts.dart';
import 'theme.dart';
import 'widgets/icon_controls.dart';
import 'widgets/selection_readout.dart';

class BuildStatusBar extends StatelessWidget {
  const BuildStatusBar({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final layer = editor.selectedLayer;
    final path = <String>[];
    for (var l = layer; l != null; l = editor.document.parentOf(l.id)) {
      path.insert(0, l.name);
    }
    final count = editor.selection.length;
    final notice = editor.notice;
    const small = TextStyle(fontSize: 12, color: Palette.muted);
    Widget divider() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(height: 14, child: VerticalDivider(width: 1)),
    );
    final centre = editor.viewport.center(Offset.zero);
    return Container(
      height: Metrics.statusHeight,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: const BoxDecoration(
        color: Palette.paper,
        border: Border(top: BorderSide(color: Palette.panelBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  // What is selected: the selection box's size.
                  SelectionReadout(editor: editor),
                  const SizedBox(width: 12),
                  if (notice != null)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.error_outline,
                        size: 14,
                        color: Palette.invalid,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      notice ?? toolPrompt(editor),
                      overflow: TextOverflow.ellipsis,
                      style: notice == null
                          ? small
                          : const TextStyle(
                              fontSize: 12,
                              color: Palette.invalid,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (path.isNotEmpty) ...[
            Text(path.join(' › '), style: small),
            if (count > 0) Text('  ·  $count selected', style: small),
            divider(),
          ],
          // Zoom changes arrive on viewChanges, which does not rebuild the
          // screen, so the readouts listen for it themselves.
          ListenableBuilder(
            listenable: editor.viewChanges,
            builder: (context, _) => _ScaleReadout(editor: editor),
          ),
          divider(),
          IconAction(
            iconData: Icons.remove,
            label: 'Zoom out',
            size: 22,
            onPressed: () => editor.zoomAt(centre, -1),
          ),
          Tooltip(
            message: 'Camera height. Click to fit drawing',
            child: InkWell(
              onTap: editor.fitDrawing,
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 72,
                child: ListenableBuilder(
                  listenable: editor.viewChanges,
                  builder: (context, _) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.photo_camera_outlined,
                        size: 14,
                        color: Palette.muted,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _cameraHeight(editor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconAction(
            iconData: Icons.add,
            label: 'Zoom in',
            size: 22,
            onPressed: () => editor.zoomAt(centre, 1),
          ),
        ],
      ),
    );
  }
}

/// The camera's height above the ground in the user's units, such as
/// "100 ft" or "7.4 ft".
String _cameraHeight(EditorController editor) {
  final units = editor.settings.units;
  final value = units.fromMetres(editor.camera.height);
  final text = value
      .toStringAsFixed(value < 9.95 ? 1 : 0)
      .replaceFirst(RegExp(r'\.0$'), '');
  return '$text ${units.symbol}';
}

/// A bar one grid cell wide, labelled with the length it represents.
class _ScaleReadout extends StatelessWidget {
  const _ScaleReadout({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final cell = editor.camera.gridCellMetres(editor.settings.units);
    final width = cell * editor.camera.pixelsPerMetreNow;
    return Tooltip(
      message:
          'One grid square is ${editor.settings.units.format(cell)} across',
      child: Row(
        children: [
          Container(
            width: width,
            height: 6,
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: Palette.muted),
                right: BorderSide(color: Palette.muted),
                bottom: BorderSide(color: Palette.muted),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            editor.settings.units.format(cell),
            style: const TextStyle(fontSize: 12, color: Palette.muted),
          ),
        ],
      ),
    );
  }
}
