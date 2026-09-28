import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/editor_controller.dart';
import '../../domain/land_rules.dart';
import '../../domain/layer.dart';
import '../canvas/scene_painter.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../widgets/panel.dart';

/// Each property with its zones listed under it. A layer expands to show
/// its shapes, top of the stack first.
class LayersBody extends StatefulWidget {
  const LayersBody({super.key, required this.editor});

  final EditorController editor;

  @override
  State<LayersBody> createState() => _LayersBodyState();
}

class _LayersBodyState extends State<LayersBody> {
  final _expanded = <String>{};

  /// The Reference layer starts open, so each image's row is in view.
  bool _referenceExpanded = true;

  EditorController get editor => widget.editor;

  @override
  Widget build(BuildContext context) {
    final document = editor.document;
    final reference = document.references.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReferenceRow(
                editor: editor,
                expanded: _referenceExpanded,
                onToggle: () =>
                    setState(() => _referenceExpanded = !_referenceExpanded),
              ),
              // Top of the layer first, as with shapes.
              if (_referenceExpanded)
                for (final image in document.references.reversed)
                  _ImageRow(editor: editor, imageId: image.id),
            ],
          );
    if (document.propertyIds.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EmptyPanelText('Add a property to start.'),
          ?reference,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in document.drawingOrder) ...[
          _LayerRow(
            editor: editor,
            layer: document.layers[id]!,
            expanded: _expanded.contains(id),
            onToggle: () => setState(
              () => _expanded.contains(id)
                  ? _expanded.remove(id)
                  : _expanded.add(id),
            ),
          ),
          if (_expanded.contains(id))
            for (final shapeId in document.geometryOf(id).stack.reversed)
              _ShapeRow(
                editor: editor,
                layer: document.layers[id]!,
                shapeId: shapeId,
              ),
        ],
        // The reference picture is drawn under all land, so it is listed
        // last.
        ?reference,
      ],
    );
  }
}

/// The Reference layer's row, always at the bottom of Layers: every
/// reference image sits in it, listed as its own row when expanded.
/// Clicking it shows the layer's Properties (where images are added);
/// hover reveals lock-all and delete-all.
class _ReferenceRow extends StatefulWidget {
  const _ReferenceRow({
    required this.editor,
    required this.expanded,
    required this.onToggle,
  });

  final EditorController editor;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<_ReferenceRow> createState() => _ReferenceRowState();
}

class _ReferenceRowState extends State<_ReferenceRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final images = editor.document.references;
    final selected = editor.referenceLayerSelected;
    final allLocked = images.every((image) => image.locked);
    return Semantics(
      selected: selected,
      button: true,
      label: 'Reference, ${images.length} images${allLocked ? ', locked' : ''}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: selected ? Palette.wash : Colors.transparent,
          borderRadius: BorderRadius.circular(Metrics.radius),
          child: InkWell(
            onTap: editor.selectReferenceLayer,
            borderRadius: BorderRadius.circular(Metrics.radius),
            hoverColor: Palette.hover,
            child: SizedBox(
              height: 30,
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: InkResponse(
                      onTap: widget.onToggle,
                      radius: 12,
                      child: Semantics(
                        button: true,
                        label: widget.expanded
                            ? 'Hide images of Reference'
                            : 'Show images of Reference',
                        child: Icon(
                          widget.expanded
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 16,
                          color: Palette.muted,
                        ),
                      ),
                    ),
                  ),
                  const ExcludeSemantics(
                    child: Icon(
                      Icons.image_outlined,
                      size: 13,
                      color: Palette.muted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      images.length > 1
                          ? 'Reference  ·  ${images.length}'
                          : 'Reference',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected
                            ? Palette.accent
                            : (allLocked ? Palette.muted : Palette.ink),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: allLocked || _hovered || selected ? 1 : 0,
                    child: IconAction(
                      iconData: allLocked
                          ? Icons.lock_outline
                          : Icons.lock_open_outlined,
                      label: allLocked
                          ? 'Unlock every image'
                          : 'Lock every image',
                      selected: allLocked,
                      size: 26,
                      onPressed: () =>
                          editor.setAllReferencesLocked(!allLocked),
                    ),
                  ),
                  Opacity(
                    opacity: _hovered || selected ? 1 : 0,
                    child: IconAction(
                      iconData: Icons.delete_outline,
                      label: 'Delete Reference',
                      tooltip: 'Delete Reference and all its images',
                      size: 26,
                      onPressed: editor.removeReferenceLayer,
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One reference image inside the Reference layer: its name and whether
/// its scale is set, with hover buttons to reorder, lock and delete it.
/// It is renamed in Properties.
class _ImageRow extends StatefulWidget {
  const _ImageRow({required this.editor, required this.imageId});

  final EditorController editor;
  final String imageId;

  @override
  State<_ImageRow> createState() => _ImageRowState();
}

class _ImageRowState extends State<_ImageRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final images = editor.document.references;
    final index = images.indexWhere((i) => i.id == widget.imageId);
    final image = images[index];
    final name = image.displayName;
    final selected = editor.selectedImage?.id == image.id;
    final showActions = _hovered || selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: selected ? Palette.wash : Colors.transparent,
        borderRadius: BorderRadius.circular(Metrics.radius),
        child: InkWell(
          onTap: () => editor.selectReference(image.id),
          borderRadius: BorderRadius.circular(Metrics.radius),
          hoverColor: Palette.hover,
          child: SizedBox(
            height: 26,
            child: Row(
              children: [
                const SizedBox(width: 26),
                const Icon(
                  Icons.photo_outlined,
                  size: 12,
                  color: Palette.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: name),
                        if (!image.isCalibrated)
                          const TextSpan(
                            text: '  no scale',
                            style: TextStyle(
                              color: Palette.muted,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? Palette.accent
                          : (image.locked ? Palette.muted : Palette.ink),
                    ),
                  ),
                ),
                if (showActions) ...[
                  IconAction(
                    iconData: Icons.arrow_upward,
                    label: 'Move $name up',
                    size: 22,
                    onPressed: index < images.length - 1
                        ? () => editor.moveReference(image.id, up: true)
                        : null,
                  ),
                  IconAction(
                    iconData: Icons.arrow_downward,
                    label: 'Move $name down',
                    size: 22,
                    onPressed: index > 0
                        ? () => editor.moveReference(image.id, up: false)
                        : null,
                  ),
                ],
                if (showActions || image.locked)
                  IconAction(
                    iconData: image.locked
                        ? Icons.lock_outline
                        : Icons.lock_open_outlined,
                    label: image.locked ? 'Unlock $name' : 'Lock $name',
                    selected: image.locked,
                    size: 22,
                    onPressed: () => editor.updateReference(
                      image.locked
                          ? 'Unlock reference image'
                          : 'Lock reference image',
                      image.withLocked(!image.locked),
                    ),
                  ),
                if (showActions)
                  IconAction(
                    iconData: Icons.delete_outline,
                    label: 'Delete $name',
                    size: 22,
                    onPressed: () => editor.removeReference(image.id),
                  ),
                const SizedBox(width: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LayerRow extends StatefulWidget {
  const _LayerRow({
    required this.editor,
    required this.layer,
    required this.expanded,
    required this.onToggle,
  });

  final EditorController editor;
  final Layer layer;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<_LayerRow> createState() => _LayerRowState();
}

class _LayerRowState extends State<_LayerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final layer = widget.layer;
    // While the reference picture is selected, its row is the highlighted
    // one; the land layer stays the drawing target but is not shown as
    // selected.
    final selected =
        editor.selectedLayerId == layer.id &&
        !editor.referenceSelected &&
        !editor.referenceLayerSelected;
    final active = editor.document.isActive(layer.id);
    final problem = editor.document.problemOf(layer.id);
    final depth = layer.kind == LayerKind.property ? 0 : 1;
    final shapeCount = editor.document.geometryOf(layer.id).stack.length;
    // Locked by a layer around this one: shown, but toggled on that layer.
    final lockedAbove = !layer.locked && editor.document.isLocked(layer.id);
    final locked = layer.locked || lockedAbove;
    final status = [
      problem != null ? 'invalid' : (active ? 'active' : 'inactive'),
      if (locked) 'locked',
    ].join(', ');
    return Semantics(
      selected: selected,
      button: true,
      label: '${layer.name}, ${layer.kind.label}, $status',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: selected ? Palette.wash : Colors.transparent,
          borderRadius: BorderRadius.circular(Metrics.radius),
          child: InkWell(
            onTap: () => editor.selectLayer(layer.id),
            borderRadius: BorderRadius.circular(Metrics.radius),
            hoverColor: Palette.hover,
            child: SizedBox(
              height: 30,
              child: Row(
                children: [
                  SizedBox(width: depth * 14.0),
                  SizedBox(
                    width: 20,
                    child: shapeCount == 0
                        ? null
                        : InkResponse(
                            onTap: widget.onToggle,
                            radius: 12,
                            child: Semantics(
                              button: true,
                              label: widget.expanded
                                  ? 'Hide shapes of ${layer.name}'
                                  : 'Show shapes of ${layer.name}',
                              child: Icon(
                                widget.expanded
                                    ? Icons.expand_more
                                    : Icons.chevron_right,
                                size: 16,
                                color: Palette.muted,
                              ),
                            ),
                          ),
                  ),
                  // A swatch in the layer's colour, hollow until it is active.
                  ExcludeSemantics(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: active ? layerColor(layer) : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: problem != null
                              ? Palette.invalid
                              : layerColor(layer),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      shapeCount > 1
                          ? '${layer.name}  ·  $shapeCount'
                          : layer.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected
                            ? Palette.accent
                            : (locked ? Palette.muted : Palette.ink),
                      ),
                    ),
                  ),
                  if (problem != null)
                    ExcludeSemantics(
                      child: Tooltip(
                        message: problem,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.error_outline,
                            size: 15,
                            color: Palette.invalid,
                          ),
                        ),
                      ),
                    ),
                  // Lock stays visible while locked so the state reads at a
                  // glance; otherwise, like Delete, it shows on hover or
                  // selection to keep the list calm.
                  Opacity(
                    opacity: locked || _hovered || selected ? 1 : 0,
                    child: IconAction(
                      iconData: locked
                          ? Icons.lock_outline
                          : Icons.lock_open_outlined,
                      label: layer.locked
                          ? 'Unlock ${layer.name}'
                          : 'Lock ${layer.name}',
                      tooltip: lockedAbove
                          ? editor.lockNotice(layer.id)
                          : (layer.locked
                                ? 'Unlock ${layer.name}'
                                : 'Lock ${layer.name} to prevent changes'),
                      selected: layer.locked,
                      size: 26,
                      onPressed: lockedAbove
                          ? null
                          : () =>
                                editor.setLayerLocked(layer.id, !layer.locked),
                    ),
                  ),
                  Opacity(
                    opacity: _hovered || selected ? 1 : 0,
                    child: IconAction(
                      iconData: Icons.delete_outline,
                      label: 'Delete ${layer.name}',
                      tooltip: editor.deleteLayerBlocker(layer.id),
                      size: 26,
                      onPressed: editor.deleteLayerBlocker(layer.id) != null
                          ? null
                          : () => confirmDeleteLayer(context, editor, layer.id),
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One shape or circle inside an expanded layer: its label, where it sits,
/// and buttons to rename it and move it in the stack.
class _ShapeRow extends StatefulWidget {
  const _ShapeRow({
    required this.editor,
    required this.layer,
    required this.shapeId,
  });

  final EditorController editor;
  final Layer layer;
  final String shapeId;

  @override
  State<_ShapeRow> createState() => _ShapeRowState();
}

class _ShapeRowState extends State<_ShapeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final layer = widget.layer;
    final document = editor.document;
    final geometry = document.geometryOf(layer.id);
    final id = widget.shapeId;
    final label = geometry.labelOf(id);
    final closed = geometry.regionOf(id) != null;
    final outside = document.isOutsideProperty(layer.id, id);
    final where = !closed
        ? 'not closed'
        : outside
        ? 'outside ${document.layers[layer.parentId]!.name}'
        : null;
    final stack = geometry.stack;
    final index = stack.indexOf(id);
    final selected =
        editor.selectedLayerId == layer.id && editor.selection.contains(id);
    final editable = editor.lockNotice(layer.id) == null;
    final showActions = _hovered || selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: selected ? Palette.wash : Colors.transparent,
        borderRadius: BorderRadius.circular(Metrics.radius),
        child: InkWell(
          // Shift-click adds or removes the shape, e.g. to pick shapes for
          // a Boolean in Operations.
          onTap: () => editor.selectObject(
            layer.id,
            id,
            toggle: HardwareKeyboard.instance.isShiftPressed,
          ),
          borderRadius: BorderRadius.circular(Metrics.radius),
          hoverColor: Palette.hover,
          child: SizedBox(
            height: 26,
            child: Row(
              children: [
                SizedBox(
                  width: (layer.kind == LayerKind.property ? 0 : 14) + 26,
                ),
                Icon(
                  geometry.circles.containsKey(id)
                      ? Icons.circle_outlined
                      : Icons.pentagon_outlined,
                  size: 12,
                  color: where == null ? Palette.muted : Palette.invalid,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: label),
                        if (where != null)
                          TextSpan(
                            text: '  $where',
                            style: const TextStyle(
                              color: Palette.invalid,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? Palette.accent : Palette.ink,
                    ),
                  ),
                ),
                if (showActions && editable) ...[
                  IconAction(
                    iconData: Icons.arrow_upward,
                    label: 'Move $label up',
                    size: 22,
                    onPressed: index < stack.length - 1
                        ? () => editor.moveShape(layer.id, id, up: true)
                        : null,
                  ),
                  IconAction(
                    iconData: Icons.arrow_downward,
                    label: 'Move $label down',
                    size: 22,
                    onPressed: index > 0
                        ? () => editor.moveShape(layer.id, id, up: false)
                        : null,
                  ),
                  IconAction(
                    iconData: Icons.edit_outlined,
                    label: 'Rename $label',
                    size: 22,
                    onPressed: () async {
                      final name = await askForShapeName(
                        context,
                        geometry.shapes[id]?.label ??
                            geometry.circles[id]?.label ??
                            label,
                      );
                      if (name != null) {
                        editor.renameShape(layer.id, id, name);
                      }
                    },
                  ),
                ],
                const SizedBox(width: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Add property / zone buttons shown under the layer tree.
class LayerActions extends StatelessWidget {
  const LayerActions({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    Widget add(LayerKind kind) {
      final blocker = editor.addLayerBlocker(kind);
      final enabled = blocker == null;
      final colour = enabled ? Palette.ink : Palette.faint;
      return Expanded(
        child: Tooltip(
          message: blocker ?? 'Add ${kind.label.toLowerCase()}',
          child: Semantics(
            button: true,
            enabled: enabled,
            label: 'Add ${kind.label.toLowerCase()}',
            excludeSemantics: true,
            child: InkWell(
              onTap: enabled ? () => editor.addLayer(kind) : null,
              borderRadius: BorderRadius.circular(Metrics.radius),
              hoverColor: Palette.hover,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 14, color: colour),
                    const SizedBox(width: 4),
                    Text(
                      kind.label,
                      style: TextStyle(fontSize: 12, color: colour),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(children: [add(LayerKind.property), add(LayerKind.zone)]),
    );
  }
}
