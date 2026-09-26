part of 'canvas_input.dart';

/// Screen distance, in logical pixels, within which a press grabs one of
/// the selected reference image's corner handles.
const double referenceHandleReach = 10;

/// Pointer input for reference images: Select moves one (drag its inside)
/// and scales it (drag a corner of the selected image), and the Reference
/// tool draws a reference line on whichever image is clicked. None of it
/// snaps: images are placed by eye, then calibrated one by one.
extension _ReferenceInput on CanvasInput {
  /// The topmost unlocked reference image under [screen], or null.
  ReferenceImage? _referenceUnder(Offset screen) {
    final world = editor.camera.toWorld(screen);
    for (final image in editor.document.references.reversed) {
      if (!image.locked && image.containsWorld(world)) return image;
    }
    return null;
  }

  /// The corner handle of the selected image under [screen], clockwise
  /// from the top-left, or null.
  int? _handleAt(Offset screen) {
    final image = editor.selectedImage;
    if (image == null || image.locked) return null;
    final corners = image.corners;
    for (var i = 0; i < corners.length; i++) {
      final at = editor.camera.toScreen(corners[i]);
      if ((at - screen).distance <= referenceHandleReach) return i;
    }
    return null;
  }

  /// A Select drag on an image. The selected image's corner handles win
  /// over everything, so it can always be resized; otherwise land on top
  /// of the images is picked first, and an image moves only when nothing
  /// else is under the pointer.
  _ReferenceDrag? _startReferenceDrag(_Press press) {
    if (editor.tool != Tool.select) return null;
    final corner = _handleAt(press.origin);
    if (corner != null) {
      return _ReferenceDrag(
        original: editor.selectedImage!,
        pressWorld: editor.camera.toWorld(press.origin),
        corner: corner,
      );
    }
    if (_selectHits(press.origin).isNotEmpty) return null;
    final image = _referenceUnder(press.origin);
    if (image == null) return null;
    editor.selectReference(image.id);
    return _ReferenceDrag(
      original: image,
      pressWorld: editor.camera.toWorld(press.origin),
    );
  }

  void _updateReferenceDrag(_ReferenceDrag drag, Offset screen) {
    final world = editor.camera.toWorld(screen);
    final original = drag.original;
    final corner = drag.corner;
    if (corner == null) {
      drag.candidate = original.movedBy(world - drag.pressWorld);
    } else {
      // Scale about the opposite corner, keeping the image's shape. The
      // pointer may not cross that corner.
      final fixed = original.corners[(corner + 2) % 4];
      final dragged = original.corners[corner];
      final sx = (dragged.x - fixed.x).sign;
      final sy = (dragged.y - fixed.y).sign;
      final across = (world.x - fixed.x) * sx / original.pixelWidth;
      final down = (world.y - fixed.y) * sy / original.pixelHeight;
      final scale = math.max(across, down);
      if (!(scale > 0) || !scale.isFinite) return;
      drag.candidate = original.scaledAbout(fixed, scale);
    }
    editor.setPreview(ReferencePreview(drag.candidate!));
  }

  void _finishReferenceDrag(_ReferenceDrag drag) {
    editor.setPreview(null);
    final candidate = drag.candidate;
    if (candidate == null) return;
    editor.updateReference(
      drag.corner == null ? 'Move reference image' : 'Scale reference image',
      candidate,
    );
    editor.selectReference(candidate.id);
  }

  /// Reference tool: the first click marks one end of a known distance on
  /// an image (the selected one if it is under the pointer, otherwise the
  /// topmost), the second click the other end on the same image. The line
  /// replaces that image's earlier one as one Undo step and clears its old
  /// distance. Other images are untouched.
  void _referenceClick(Offset screen) {
    final blocker = editor.referenceBlocker;
    if (blocker != null) return editor.showNotice(blocker);
    final world = editor.camera.toWorld(screen);
    final startId = editor.referenceLineImageId;
    final start = editor.referenceLineStart;
    if (start == null || startId == null) {
      final image = _lineTargetAt(world);
      if (image == null) {
        return editor.showNotice('Click on an unlocked reference image');
      }
      editor.selectReference(image.id);
      editor.setReferenceLineStart(image.id, image.toPixel(world));
      return editor.showNotice(null);
    }
    final image = editor.document.referenceById(startId)!;
    if (!image.containsWorld(world)) {
      return editor.showNotice(
        'Click the other end on the same image (${image.displayName})',
      );
    }
    final pixel = image.toPixel(world);
    final length =
        (editor.camera.toScreen(image.toWorld(start)) - screen).distance;
    if (length < PointerReach.point) {
      return editor.showNotice('Click farther from the first end');
    }
    editor.updateReference('Reference line', image.withLine(start, pixel));
    editor.setReferenceLineStart(null, null);
    editor.showNotice(null);
  }

  /// The image a new line starts on: the selected image when the click is
  /// on it, so a line can go on an image lying under another; otherwise
  /// the topmost unlocked image there.
  ReferenceImage? _lineTargetAt(Vec world) {
    final selected = editor.selectedImage;
    if (selected != null && !selected.locked && selected.containsWorld(world)) {
      return selected;
    }
    for (final image in editor.document.references.reversed) {
      if (!image.locked && image.containsWorld(world)) return image;
    }
    return null;
  }

  /// Reference tool: a press that starts dragging marks the line's first
  /// end where the press began, so the line can be dragged out and let
  /// go at its other end, as well as drawn with two clicks.
  void _startReferenceLineDrag(_Press press) {
    if (editor.referenceLineStart != null) return;
    _referenceClick(press.origin);
  }

  ReferenceLinePreview? _referenceLinePreview(Offset screen) {
    final image = editor.document.referenceById(editor.referenceLineImageId);
    final start = editor.referenceLineStart;
    if (image == null || start == null) return null;
    final world = editor.camera.toWorld(screen);
    return ReferenceLinePreview(
      image.toWorld(start),
      world,
      valid: image.containsWorld(world),
    );
  }
}

/// A Select drag on a reference image: a move, or a scale from the
/// [corner] handle (clockwise from the top-left).
class _ReferenceDrag {
  _ReferenceDrag({
    required this.original,
    required this.pressWorld,
    this.corner,
  });

  final ReferenceImage original;
  final Vec pressWorld;
  final int? corner;

  /// The image as it would be if released now.
  ReferenceImage? candidate;
}
