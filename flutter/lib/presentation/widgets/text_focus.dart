import 'package:flutter/widgets.dart';

/// Whether the keyboard focus is in a text box, so typing (letters, Enter,
/// Delete) belongs to the box and not to the editor's shortcuts.
///
/// A text box's focus node sits on a `Focus` widget inside its
/// [EditableText], so the check looks up from the focused widget rather
/// than at it. Checking only the focused widget missed every box given its
/// own focus node, and shortcuts then swallowed Enter and letter keys.
bool textFieldHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}
