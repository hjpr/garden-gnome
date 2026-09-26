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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
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
      ),
      onChanged: _onChanged,
      onSubmitted: (_) => _commit(),
    );
  }
}
