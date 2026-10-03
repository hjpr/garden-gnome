import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A text box that keeps its value on Enter or when it loses focus, and
/// puts the stored value back on Esc. [commit] returns an error to show,
/// or null when the value was taken. [hint] shows the default used while
/// the box is empty.
///
/// Local to the garden field, unlike Plan drafts registered for drawing
/// save, undo and layer-switch settlement.
class CommitField extends StatefulWidget {
  const CommitField({
    super.key,
    required this.value,
    required this.commit,
    this.hint,
    this.label,
    this.maxLines = 1,
    this.enabled = true,
    this.suffix,
  });

  final String value;
  final String? Function(String text) commit;
  final String? hint;

  /// Read by screen readers.
  final String? label;
  final int maxLines;
  final bool enabled;
  final String? suffix;

  @override
  State<CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<CommitField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(CommitField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _text.text) {
      _text.text = widget.value;
      _error = null;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    if (_text.text == widget.value) {
      if (_error != null) setState(() => _error = null);
      return;
    }
    final error = widget.commit(_text.text);
    setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _text.text = widget.value;
        setState(() => _error = null);
        _focus.unfocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Semantics(
      label: widget.label,
      textField: true,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        enabled: widget.enabled,
        maxLines: widget.maxLines,
        minLines: 1,
        style: const TextStyle(fontSize: 13),
        textInputAction: widget.maxLines == 1
            ? TextInputAction.done
            : TextInputAction.newline,
        onSubmitted: (_) => _commit(),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(fontSize: 13, color: Palette.faint),
          errorText: _error,
          errorStyle: const TextStyle(fontSize: 11),
          suffixText: widget.suffix,
          suffixStyle: const TextStyle(fontSize: 12, color: Palette.muted),
        ),
      ),
    ),
  );
}
