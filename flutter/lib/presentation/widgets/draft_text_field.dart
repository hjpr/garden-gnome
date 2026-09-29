import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/drafts.dart';
import '../../application/editor_controller.dart';
import '../theme.dart';

/// A Properties text box whose typing is held as a draft until it is
/// applied with Enter or by leaving the box, and undone with Escape.
///
/// The draft remembers the layer it belongs to, so it is never applied to
/// a different layer.
class DraftTextField extends StatefulWidget {
  const DraftTextField({
    super.key,
    required this.editor,
    required this.draftKey,
    required this.layerId,
    required this.committedText,
    required this.label,
    required this.apply,
    this.check = _anyText,
    this.hint,
    this.enabled = true,
    this.onStep,
  });

  final EditorController editor;
  final String draftKey;
  final String layerId;
  final String committedText;
  final String label;
  final String? hint;
  final bool enabled;
  final String? Function(String text) check;
  final void Function(String text) apply;

  /// When set, the box shows small up and down arrows at its right, and
  /// the Up and Down keys work too. Called with the text as typed so far
  /// and +1 or -1; Shift steps further (the owner decides how far).
  final void Function(String text, int direction, {required bool big})? onStep;

  static String? _anyText(String _) => null;

  @override
  State<DraftTextField> createState() => _DraftTextFieldState();
}

class _DraftTextFieldState extends State<DraftTextField> {
  late final TextEditingController _text;
  late final FocusNode _focus;
  String? _error;

  DraftRegistry get _drafts => widget.editor.drafts;

  @override
  void initState() {
    super.initState();
    final pending = _drafts[widget.draftKey];
    _text = TextEditingController(text: pending?.text ?? widget.committedText);
    _focus = FocusNode(onKeyEvent: _onKey)..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(DraftTextField old) {
    super.didUpdateWidget(old);
    // Show the stored value when it changes elsewhere (for example Undo)
    // and nothing is being typed.
    if (_drafts[widget.draftKey] == null &&
        _text.text != widget.committedText) {
      _text.text = widget.committedText;
      _error = null;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _drafts.update(
      widget.draftKey,
      PropertyDraft(
        layerId: widget.layerId,
        text: text,
        committedText: widget.committedText,
        check: widget.check,
        apply: widget.apply,
      ),
    );
    widget.editor.draftsChanged();
    if (_error != null) setState(() => _error = null);
  }

  void _commit() {
    final problem = _drafts.commit(widget.draftKey);
    setState(() => _error = problem);
  }

  void _revert() {
    _drafts.discard(widget.draftKey);
    _text.text = widget.committedText;
    setState(() => _error = null);
    widget.editor.draftsChanged();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus && !widget.editor.suspendDraftSettlement) _commit();
  }

  /// Steps the value from what is in the box now. The typed draft is
  /// dropped first, so the stepped value shows once it is applied.
  void _step(int direction) {
    final text = _text.text;
    _drafts.discard(widget.draftKey);
    setState(() => _error = null);
    widget.onStep!(
      text,
      direction,
      big: HardwareKeyboard.instance.isShiftPressed,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.onStep != null &&
        (event is KeyDownEvent || event is KeyRepeatEvent)) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _step(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _step(-1);
        return KeyEventResult.handled;
      }
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _drafts[widget.draftKey] != null) {
      _revert();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      focusNode: _focus,
      enabled: widget.enabled,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: widget.hint,
        errorText: _error,
        errorMaxLines: 3,
        errorStyle: const TextStyle(fontSize: 11, color: Palette.invalid),
        suffixIcon: widget.onStep == null
            ? null
            : _StepArrows(
                label: widget.label,
                onStep: widget.enabled ? _step : null,
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 22, maxWidth: 22),
      ),
      onChanged: _onChanged,
      onSubmitted: (_) => _commit(),
    );
  }
}

/// Two small stacked arrows at the right of a number box: up adds one
/// step, down takes one away. Greyed out when the box is.
///
/// The triangles are drawn rather than taken from icon glyphs, whose ink
/// is not centred in the glyph box and sat the pair a few pixels low.
class _StepArrows extends StatelessWidget {
  const _StepArrows({required this.label, required this.onStep});

  final String label;
  final void Function(int direction)? onStep;

  /// Height of each arrow's click area; the pair is centred in the box.
  static const _half = 11.0;

  /// Space between the two click areas.
  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final colour = onStep == null ? Palette.faint : Palette.muted;
    Widget arrow(int direction, String name) => SizedBox(
      width: 18,
      height: _half,
      child: Semantics(
        button: true,
        label: '$name $label',
        excludeSemantics: true,
        child: InkWell(
          onTap: onStep == null ? null : () => onStep!(direction),
          borderRadius: BorderRadius.circular(3),
          hoverColor: Palette.hover,
          child: CustomPaint(
            painter: _TrianglePainter(up: direction > 0, colour: colour),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            arrow(1, 'Increase'),
            // A small dead strip between them, so a click near the middle
            // does not land on the wrong arrow.
            const SizedBox(height: _gap),
            arrow(-1, 'Decrease'),
          ],
        ),
      ),
    );
  }
}

/// A small filled triangle, pointing up or down, placed so the up and
/// down pair mirror each other about the line between them.
class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.up, required this.colour});

  final bool up;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    const half = 3.5; // half the base width
    const height = 3.5;
    const gap = 1.5; // from the pair's centre line to each triangle's base
    final cx = size.width / 2;
    final path = Path();
    if (up) {
      // Base near the bottom edge (the pair's centre), tip above it.
      final base = size.height - gap;
      path
        ..moveTo(cx - half, base)
        ..lineTo(cx + half, base)
        ..lineTo(cx, base - height);
    } else {
      final base = gap;
      path
        ..moveTo(cx - half, base)
        ..lineTo(cx + half, base)
        ..lineTo(cx, base + height);
    }
    canvas.drawPath(path..close(), Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) =>
      old.up != up || old.colour != colour;
}
