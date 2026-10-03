import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../theme.dart';
import '../widgets/icon_controls.dart';

class ReferenceLayerRows extends StatelessWidget {
  const ReferenceLayerRows({
    super.key,
    required this.editor,
    required this.expanded,
    required this.onToggle,
  });

  final EditorController editor;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _ReferenceRow(editor: editor, expanded: expanded, onToggle: onToggle),
      if (expanded)
        for (final image in editor.document.references.reversed)
          _ImageRow(editor: editor, imageId: image.id),
    ],
  );
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
    final allLocked =
        images.isNotEmpty && images.every((image) => image.locked);
    final hidden = editor.referenceHidden;
    return Semantics(
      selected: selected,
      button: true,
      label:
          'Reference, ${images.length} images'
          '${allLocked ? ', locked' : ''}${hidden ? ', hidden' : ''}',
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
                    child: images.isEmpty
                        ? null
                        : InkResponse(
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
                    opacity: hidden || _hovered || selected ? 1 : 0,
                    child: IconAction(
                      iconData: hidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      label: hidden ? 'Show Reference' : 'Hide Reference',
                      selected: hidden,
                      size: 26,
                      onPressed: () => editor.setLayerHidden(
                        EditorController.referenceLayerKey,
                        !hidden,
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
                      onPressed: images.isEmpty
                          ? null
                          : () => editor.setAllReferencesLocked(!allLocked),
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
