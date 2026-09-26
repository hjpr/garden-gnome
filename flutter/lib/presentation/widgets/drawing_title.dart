import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'panel.dart';

/// The drawing's name in the middle of the header, with a pencil to
/// rename it in place. Enter or clicking away keeps the new name; Esc
/// puts the old one back. A blank name is ignored.
class DrawingTitle extends StatefulWidget {
  const DrawingTitle({
    super.key,
    required this.title,
    required this.dirty,
    required this.onRename,
  });

  final String title;
  final bool dirty;
  final ValueChanged<String> onRename;

  @override
  State<DrawingTitle> createState() => _DrawingTitleState();
}

class _DrawingTitleState extends State<DrawingTitle> {
  static const _style = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static final _border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(Metrics.radius),
    borderSide: const BorderSide(color: Palette.panelBorder),
  );

  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'drawing title');
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _finish(keep: true);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    _text
      ..text = widget.title
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.title.length,
      );
    setState(() => _editing = true);
    _focus.requestFocus();
  }

  void _finish({required bool keep}) {
    if (!_editing) return;
    setState(() => _editing = false);
    if (keep) widget.onRename(_text.text);
    if (_focus.hasFocus) _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return SizedBox(
        width: 280,
        child: Focus(
          // Esc cancels here instead of reaching the editor's shortcuts.
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _finish(keep: false);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Semantics(
            label: 'Drawing name',
            child: TextField(
              controller: _text,
              focusNode: _focus,
              style: _style,
              textAlign: TextAlign.center,
              // Styled like the menus: white with a thin grey border,
              // rather than the filled, green-focused panel inputs.
              decoration: InputDecoration(
                filled: true,
                fillColor: Palette.paper,
                hoverColor: Colors.transparent,
                enabledBorder: _border,
                focusedBorder: _border,
                border: _border,
              ),
              onSubmitted: (_) => _finish(keep: true),
            ),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: GestureDetector(
            onDoubleTap: _start,
            child: Text(
              widget.title,
              overflow: TextOverflow.ellipsis,
              style: _style,
            ),
          ),
        ),
        if (widget.dirty)
          const Tooltip(
            message: 'Unsaved changes',
            child: Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.circle, size: 7, color: Palette.muted),
            ),
          ),
        const SizedBox(width: 4),
        IconAction(
          iconData: Icons.edit_outlined,
          label: 'Rename drawing',
          size: 24,
          onPressed: _start,
        ),
      ],
    );
  }
}
