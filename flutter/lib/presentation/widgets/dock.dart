import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../application/workspace_settings.dart';
import '../theme.dart';
import 'icon_controls.dart';

/// The icon that stands for a panel on a dock's rail.
extension PanelIcon on PanelId {
  IconData get icon => switch (this) {
    PanelId.tools => Icons.draw_outlined,
    PanelId.seeds => Icons.spa_outlined,
    PanelId.greenhouse => Icons.house_siding_outlined,
    PanelId.operations => Icons.join_full_outlined,
    PanelId.settings => Icons.tune,
    PanelId.properties => Icons.info_outline,
    PanelId.layers => Icons.layers_outlined,
  };
}

/// Builds the panel for [panel], which sits at [index] in its dock.
typedef DockPanelBuilder = Widget Function(PanelId panel, int index);

/// A column of panels at one edge of the window.
///
/// A slim rail runs along the window edge. Clicking the rail folds the
/// panels away or brings them back; its icons show which panels are open
/// and open one directly. Panels are dragged by their grip to reorder them.
class Dock extends StatelessWidget {
  const Dock({
    super.key,
    required this.side,
    required this.editor,
    required this.width,
    required this.buildPanel,
    this.onResize,
  });

  final DockSide side;
  final EditorController editor;

  /// Width of the panel column when open, not counting the rail.
  final double width;
  final DockPanelBuilder buildPanel;

  /// Called with the pointer's horizontal travel while the dock's inner
  /// edge is dragged: positive widens the dock.
  final ValueChanged<double>? onResize;

  bool get _isLeft => side == DockSide.left;

  @override
  Widget build(BuildContext context) {
    final settings = editor.settings;
    final open = settings.docks.isOpen(side);
    final visible = [
      for (final id in settings.docks.orderOf(side))
        if (id.availableIn(editor.mode) && !settings.hiddenPanels.contains(id))
          id,
    ];
    final edge = BorderSide(color: Palette.panelBorder);

    final panels = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: open ? width : 0,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Palette.chrome,
        border: Border(
          left: _isLeft ? BorderSide.none : edge,
          right: _isLeft ? edge : BorderSide.none,
        ),
      ),
      child: OverflowBox(
        alignment: _isLeft ? Alignment.centerRight : Alignment.centerLeft,
        minWidth: width,
        maxWidth: width,
        // Folded panels stay built, so their state and scroll position
        // survive, but they cannot be reached by keyboard or screen reader.
        child: ExcludeSemantics(
          excluding: !open,
          child: ExcludeFocus(
            excluding: !open,
            child: visible.isEmpty
                ? const Center(
                    child: Text(
                      'All panels are hidden.\nShow them from the View menu.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Palette.muted),
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.only(bottom: 6),
                    itemCount: visible.length,
                    onReorder: (from, to) =>
                        editor.movePanel(side, visible, from, to),
                    proxyDecorator: (child, _, animation) => Material(
                      color: Colors.transparent,
                      elevation: 8 * animation.value,
                      shadowColor: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                      child: child,
                    ),
                    itemBuilder: (context, i) => KeyedSubtree(
                      key: ValueKey(visible[i]),
                      child: buildPanel(visible[i], i),
                    ),
                  ),
          ),
        ),
      ),
    );

    final rail = _Rail(
      side: side,
      editor: editor,
      visible: visible,
      open: open,
    );
    final grip = open && onResize != null
        ? _ResizeEdge(onDrag: (dx) => onResize!(_isLeft ? dx : -dx))
        : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _isLeft ? [rail, panels, ?grip] : [?grip, panels, rail],
    );
  }
}

/// The slim strip along the window edge: fold toggle plus one icon per panel.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.side,
    required this.editor,
    required this.visible,
    required this.open,
  });

  final DockSide side;
  final EditorController editor;
  final List<PanelId> visible;
  final bool open;

  String get _sideName => side == DockSide.left ? 'left' : 'right';

  void _toggle() => editor.setDockOpen(side, !open);

  /// Opens the dock on [panel], or folds that panel when it is already open.
  void _focusPanel(PanelId panel) {
    final minimized = editor.settings.minimizedPanels.contains(panel);
    if (!open) {
      editor.setDockOpen(side, true);
      if (minimized) editor.setPanelMinimized(panel, false);
    } else {
      editor.setPanelMinimized(panel, !minimized);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pointsLeft = (side == DockSide.left) == open;
    final edge = BorderSide(color: Palette.panelBorder);
    return Semantics(
      container: true,
      label: '${_sideName[0].toUpperCase()}${_sideName.substring(1)} panels',
      child: Material(
        color: Palette.chrome,
        shape: Border(
          left: side == DockSide.right ? edge : BorderSide.none,
          right: side == DockSide.left ? edge : BorderSide.none,
        ),
        child: InkWell(
          // The whole strip is a target: click anywhere on it to fold or open.
          onTap: _toggle,
          hoverColor: Palette.hover,
          mouseCursor: SystemMouseCursors.click,
          child: SizedBox(
            width: Metrics.railWidth,
            child: Column(
              children: [
                const SizedBox(height: 6),
                IconAction(
                  iconData: pointsLeft
                      ? Icons.keyboard_double_arrow_left
                      : Icons.keyboard_double_arrow_right,
                  label: open
                      ? 'Collapse $_sideName panels'
                      : 'Expand $_sideName panels',
                  onPressed: _toggle,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Divider(),
                ),
                for (final panel in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: IconAction(
                      iconData: panel.icon,
                      label: panel.label,
                      selected:
                          open &&
                          !editor.settings.minimizedPanels.contains(panel),
                      onPressed: () => _focusPanel(panel),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin strip on the dock's inner edge. Dragging it sideways resizes the
/// dock; it shows a resize cursor and a faint accent line on hover.
class _ResizeEdge extends StatefulWidget {
  const _ResizeEdge({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  State<_ResizeEdge> createState() => _ResizeEdgeState();
}

class _ResizeEdgeState extends State<_ResizeEdge> {
  bool _active = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Resize panels',
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        child: SizedBox(
          width: 6,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 2,
              color: _active || _dragging
                  ? Palette.accent.withValues(alpha: 0.6)
                  : Palette.accent.withValues(alpha: 0),
            ),
          ),
        ),
      ),
    ),
  );
}
