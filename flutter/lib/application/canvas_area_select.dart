part of 'canvas_input.dart';

/// Screen pixels the pointer must travel before a lasso records another
/// corner, so the outline stays light while following the hand closely.
const double _lassoStep = 3;

/// Pointer input for Select → Marquee and Select → Lasso: a drag that
/// starts away from anything movable draws a selection outline, and
/// letting go selects everything the outline touches.
extension _AreaSelectInput on CanvasInput {
  _AreaDrag _startAreaDrag(_Press press) => _AreaDrag(
    lasso: editor.function == ToolFunction.lasso,
    shift: press.shift,
    screen: [press.origin],
  );

  void _updateAreaDrag(_AreaDrag drag, Offset screen) {
    if (drag.lasso) {
      if ((screen - drag.screen.last).distance < _lassoStep) return;
      drag.screen.add(screen);
    } else {
      drag.screen
        ..length = 1
        ..add(screen);
    }
    final outline = _areaOutline(drag);
    final (layerId, items) = _areaPick(outline, shift: drag.shift);
    editor.setPreview(
      AreaSelectPreview(
        outline,
        lasso: drag.lasso,
        layerId: layerId,
        items: items,
      ),
    );
  }

  void _finishAreaDrag(_AreaDrag drag) {
    editor.setPreview(null);
    final (layerId, items) = _areaPick(_areaOutline(drag), shift: drag.shift);
    if (layerId == null) {
      // Nothing touched: like a click on empty ground.
      if (!drag.shift) editor.selectItem(null);
      return;
    }
    editor.selectItems(layerId, items, add: drag.shift);
  }

  /// The outline in world metres: the rectangle's four corners, or the
  /// lasso's path, which closes back to where it began.
  List<Vec> _areaOutline(_AreaDrag drag) {
    final camera = editor.camera;
    if (!drag.lasso) {
      return rectangleOutline(
        camera.toWorld(drag.screen.first),
        camera.toWorld(drag.screen.last),
      );
    }
    return [for (final p in drag.screen) camera.toWorld(p)];
  }

  /// The layer an outline selects on, and the items it would pick there.
  ///
  /// Selections live on one layer. The selected layer wins when the
  /// outline touches it, so choosing a field in Layers first lets a
  /// marquee pick field shapes under plots. Otherwise the innermost kind
  /// of layer wins, as with a click. Shift only adds to the selected
  /// layer. Locked layers are skipped.
  (String?, Set<String>) _areaPick(List<Vec> outline, {required bool shift}) {
    final document = editor.document;
    final touched = itemsTouchedAcrossLayers(
      document,
      outline,
      include: (id) => !document.isLocked(id),
    );
    final selected = editor.selectedLayerId;
    if (touched[selected] case final items?) return (selected, items);
    if (shift || touched.isEmpty) return (null, const {});
    final innermost = touched.keys.reduce(
      (best, id) =>
          document.layers[id]!.kind.index > document.layers[best]!.kind.index
          ? id
          : best,
    );
    return (innermost, touched[innermost]!);
  }
}

/// A marquee or lasso being drawn.
class _AreaDrag {
  _AreaDrag({required this.lasso, required this.shift, required this.screen});

  final bool lasso;

  /// Shift was held at the press: add to the selection.
  final bool shift;

  /// Screen positions: the press and the pointer for a marquee, the
  /// whole path for a lasso.
  final List<Offset> screen;
}
