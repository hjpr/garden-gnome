import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/canvas_input.dart';
import '../../application/editor_controller.dart';
import '../../application/hit_testing.dart';
import '../../application/previews.dart';
import '../../platform/canvas_cursor.dart';
import '../widgets/text_focus.dart';
import 'reference_image_cache.dart';
import 'scene_painter.dart';

/// The drawing viewport: routes pointer input and paints the scene.
///
/// Middle-drag, or Space with a left-drag, pans. The mouse wheel zooms
/// around the pointer. Other left-button input goes to the active tool.
class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({super.key, required this.editor});

  final EditorController editor;

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  late final CanvasInput _input = CanvasInput(widget.editor);

  /// The decoded reference picture; repaints when a decode finishes.
  final ReferenceImageCache _pictures = ReferenceImageCache();

  /// Everything that changes what the canvas shows.
  late final Listenable _repaint = Listenable.merge([
    widget.editor,
    widget.editor.viewChanges,
    _pictures,
  ]);

  /// The pointer currently panning the view, if any.
  int? _panPointer;

  /// The pointer currently driving a tool, if any.
  int? _toolPointer;

  /// Whether the mouse is over the canvas; the Select arrow shows only then.
  bool _pointerInside = false;

  @override
  void initState() {
    super.initState();
    widget.editor.addListener(_updateCursor);
  }

  /// Select picks and moves, so it shows its own arrow. Drawing tools keep
  /// the crosshair, and panning keeps the grab hand.
  void _updateCursor() {
    showSelectArrowCursor(
      _pointerInside &&
          widget.editor.tool.usesArrowCursor &&
          !_spaceHeld &&
          _panPointer == null,
    );
  }

  bool get _spaceHeld =>
      HardwareKeyboard.instance.logicalKeysPressed.contains(
        LogicalKeyboardKey.space,
      ) &&
      !textFieldHasFocus();

  void _onDown(PointerDownEvent event) {
    if (_toolPointer != null || _panPointer != null) return;
    final middle = event.buttons & kMiddleMouseButton != 0;
    final primary = event.buttons & kPrimaryMouseButton != 0;
    if (middle || (primary && _spaceHeld)) {
      _panPointer = event.pointer;
      _updateCursor();
      return;
    }
    if (!primary) return;
    _toolPointer = event.pointer;
    _input.press(
      event.localPosition,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );
    _holdTimer?.cancel();
    _holdTimer = Timer(PointerReach.hold, () => _showHoldMenu(event.position));
  }

  /// Timer that opens the "what's underneath" menu for a still press.
  Timer? _holdTimer;

  /// Lists everything under a held press so the user can pick the one
  /// they mean, e.g. a field edge hidden under a plot.
  Future<void> _showHoldMenu(Offset globalPosition) async {
    final choices = _input.takeHoldChoices();
    if (choices.isEmpty || !mounted) return;
    _toolPointer = null;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(globalPosition);
    final chosen = await showMenu<LayerHit>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        overlay.size.width - local.dx,
        overlay.size.height - local.dy,
      ),
      items: [
        for (final hit in choices)
          PopupMenuItem(
            value: hit,
            height: 34,
            // Hovering a choice highlights it on the canvas.
            child: MouseRegion(
              onEnter: (_) => widget.editor.setPreview(
                HoverPreview(hit.itemId, layerId: hit.layerId),
              ),
              child: Text(
                _input.describe(hit),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
      ],
    );
    widget.editor.setPreview(null);
    if (chosen != null) _input.choose(chosen);
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer == _panPointer) {
      widget.editor.panBy(event.delta);
    } else if (event.pointer == _toolPointer) {
      _input.move(event.localPosition);
      if (_input.isDragging) _holdTimer?.cancel();
    }
  }

  void _onUp(PointerUpEvent event) {
    _holdTimer?.cancel();
    if (event.pointer == _panPointer) {
      _panPointer = null;
      _updateCursor();
    } else if (event.pointer == _toolPointer) {
      _toolPointer = null;
      final size = context.size ?? Size.zero;
      final inside = (Offset.zero & size).contains(event.localPosition);
      if (inside || !_input.isDragging) {
        _input.release(event.localPosition);
      } else {
        _input.cancel();
      }
    }
  }

  @override
  void dispose() {
    widget.editor.removeListener(_updateCursor);
    showSelectArrowCursor(false);
    _holdTimer?.cancel();
    _pictures.dispose();
    super.dispose();
  }

  void _onCancel(PointerCancelEvent event) {
    _holdTimer?.cancel();
    if (event.pointer == _panPointer) _panPointer = null;
    if (event.pointer == _toolPointer) {
      _toolPointer = null;
      _input.cancel();
    }
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _input.isDragging) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final dy = event.scrollDelta.dy;
      if (dy == 0) return;
      widget.editor.zoomAt(event.localPosition, dy < 0 ? 1 : -1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.editor.setViewportSize(size),
        );
        return MouseRegion(
          cursor: _spaceHeld || _panPointer != null
              ? SystemMouseCursors.grab
              : widget.editor.tool.usesArrowCursor
              ? SystemMouseCursors.basic
              : SystemMouseCursors.precise,
          onEnter: (_) {
            _pointerInside = true;
            _updateCursor();
          },
          onHover: (event) {
            _updateCursor();
            _input.hover(event.localPosition);
          },
          onExit: (_) {
            _pointerInside = false;
            _updateCursor();
            if (_toolPointer == null) widget.editor.setPreview(null);
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: _onCancel,
            onPointerSignal: _onSignal,
            child: ListenableBuilder(
              // Pan, zoom and hover feedback arrive on viewChanges; they
              // redraw only this canvas, not the panels around it.
              listenable: _repaint,
              builder: (context, _) {
                final editor = widget.editor;
                return CustomPaint(
                  size: size,
                  painter: ScenePainter(
                    SceneState(
                      document: editor.document,
                      camera: editor.camera,
                      appearance: editor.settings.appearance,
                      selectedLayerId: editor.selectedLayerId,
                      selection: editor.selection,
                      preview: editor.preview,
                      lineAnchor: editor.lineAnchor,
                      joinStart: editor.joinStart,
                      units: editor.settings.units,
                      referencePictures: _pictures.sync([
                        for (final image in editor.document.references)
                          image.bytes,
                      ]),
                      referenceOpacity: editor.opacityOf,
                      selectedImageId: editor.selectedImage?.id,
                      referenceLineImageId: editor.referenceLineImageId,
                      referenceLineStart: editor.referenceLineStart,
                      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
