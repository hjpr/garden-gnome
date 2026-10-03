import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/canvas_input.dart';
import '../../application/curve_handles.dart';
import '../../application/editor_controller.dart';
import '../../application/hit_testing.dart';
import '../../application/planting.dart';
import '../../application/previews.dart';
import '../../application/tools.dart';
import '../../application/selection_box.dart';
import '../../application/transform_box.dart';
import '../../domain/grow/variety.dart';
import '../../domain/vec.dart';
import '../../platform/canvas_cursor.dart';
import '../widgets/text_focus.dart';
import 'reference_image_cache.dart';
import 'render_assets.dart';
import 'scene_painter.dart';
import 'scene_state.dart';

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
    RenderAssets.instance,
    _viewSettled,
  ]);

  /// The camera at the last paint, to tell a pan or zoom from other
  /// redraws.
  Object? _lastCamera;

  /// Whether the camera has changed within [_settleDelay].
  bool _viewMoving = false;
  Timer? _settleTimer;

  /// Fires once the view has stopped moving, to draw the full-quality
  /// Render ground again.
  final _viewSettled = ChangeNotifier();

  static const _settleDelay = Duration(milliseconds: 180);

  /// Notes a pan or zoom: Render draws cheap ground edges until the
  /// camera has been still for [_settleDelay].
  void _trackViewMotion(Object camera) {
    if (identical(camera, _lastCamera)) return;
    final first = _lastCamera == null;
    _lastCamera = camera;
    if (first) return;
    _viewMoving = true;
    _settleTimer?.cancel();
    _settleTimer = Timer(_settleDelay, () {
      _viewMoving = false;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      _viewSettled.notifyListeners();
    });
  }

  /// The pointer currently panning the view, if any.
  int? _panPointer;

  /// The pointer currently driving a tool, if any.
  int? _toolPointer;

  /// Whether the mouse is over the canvas; the Select arrow shows only then.
  bool _pointerInside = false;

  @override
  void initState() {
    super.initState();
    // Textures and feature pictures load in the background; Wireframe
    // uses the feature pictures' sizes only in Render, so load both now.
    RenderAssets.instance.ensureLoaded();
    widget.editor.addListener(_updateCursor);
  }

  /// Select picks and moves, so it shows its own arrow, and the selection
  /// box's handles show which way they scale or turn. Drawing tools keep
  /// the crosshair, and panning keeps the grab hand.
  void _updateCursor() {
    final ours =
        _pointerInside &&
        widget.editor.tool.usesArrowCursor &&
        !_spaceHeld &&
        _panPointer == null;
    // A box drag keeps its cursor even when the pointer leaves the canvas.
    final grip = _input.activeGrip;
    showCanvasCursor(switch (grip) {
      _ when !ours && !_input.isDragging => CanvasCursor.system,
      null when ours && widget.editor.function == ToolFunction.lasso =>
        CanvasCursor.lasso,
      null => ours ? CanvasCursor.arrow : CanvasCursor.system,
      BoxGrip(rotate: true) => CanvasCursor.rotate,
      BoxGrip(:final handle) when handle.sx == 0 => CanvasCursor.resizeVertical,
      BoxGrip(:final handle) when handle.sy == 0 =>
        CanvasCursor.resizeHorizontal,
      BoxGrip(:final handle) when handle.sx == handle.sy =>
        CanvasCursor.resizeDiagonalDown,
      _ => CanvasCursor.resizeDiagonalUp,
    });
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
  /// they mean, e.g. a property edge hidden under a zone.
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
      _input.move(
        event.localPosition,
        shift: HardwareKeyboard.instance.isShiftPressed,
      );
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
      _updateCursor();
    }
  }

  @override
  void dispose() {
    widget.editor.removeListener(_updateCursor);
    showCanvasCursor(CanvasCursor.system);
    _holdTimer?.cancel();
    _settleTimer?.cancel();
    _viewSettled.dispose();
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
        return DragTarget<Object>(
          // Seeds from the Seeds panel and plants from the Greenhouse
          // panel land on plantings (Plant mode).
          onWillAcceptWithDetails: (details) =>
              widget.editor.mode == EditMode.plant &&
              (details.data is VarietyProfile || details.data is TrayDrag),
          onMove: (details) => widget.editor.setPreview(
            SeedDropPreview(
              growZoneAt(widget.editor, _worldAt(details.offset)),
            ),
          ),
          onLeave: (_) => widget.editor.setPreview(null),
          onAcceptWithDetails: (details) {
            widget.editor.setPreview(null);
            final world = _worldAt(details.offset);
            switch (details.data) {
              case VarietyProfile profile:
                dropSeed(widget.editor, profile, world);
              case TrayDrag tray:
                dropTray(widget.editor, tray, world);
            }
          },
          builder: (context, _, _) => _pointerArea(size),
        );
      },
    );
  }

  /// The world point under a global screen position.
  Vec _worldAt(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    final local = box == null ? global : box.globalToLocal(global);
    return widget.editor.camera.toWorld(local);
  }

  Widget _pointerArea(Size size) {
    return Builder(
      builder: (context) {
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
            _input.hover(event.localPosition);
            _updateCursor();
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
                _trackViewMotion(editor.camera);
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
                      selectionBox: selectionBoxOf(editor),
                      guideMarkers: _input.activeGuideSet().markers,
                      showCurveHandles: visibleCurveHandles(editor).isNotEmpty,
                      viewMode: editor.settings.viewMode,
                      renderAssets: RenderAssets.instance,
                      selectedFeatureId: editor.selectedFeature?.id,
                      viewMoving: _viewMoving,
                      hiddenLayers: editor.hiddenLayerIds,
                      referenceHidden: editor.referenceHidden,
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
