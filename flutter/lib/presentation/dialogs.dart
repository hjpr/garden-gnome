import 'package:flutter/material.dart';

import '../application/editor_controller.dart';
import '../persistence/drawing_library.dart';
import 'theme.dart';

/// Asks before deleting a layer, naming everything that goes with it.
Future<void> confirmDeleteLayer(
  BuildContext context,
  EditorController editor,
  String layerId,
) async {
  final layer = editor.document.layers[layerId];
  if (layer == null) return;
  final zones = layer.children.length;
  final kind = layer.role.label.toLowerCase();
  editor.suspendDraftSettlement = true;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${layer.name}?'),
      content: Text(
        zones == 0
            ? 'This $kind will be removed. You can undo this.'
            : 'This $kind and the $zones '
                  '${zones == 1 ? 'layer' : 'layers'} in it will be removed. '
                  'You can undo this.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Palette.invalid),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  editor.suspendDraftSettlement = false;
  if (confirmed == true) editor.deleteLayer(layerId);
}

enum LeaveChoice { save, discard, cancel }

/// Save / Don't save / Cancel before leaving a drawing with unsaved work.
Future<LeaveChoice> askToSave(BuildContext context, String title) async {
  final choice = await showDialog<LeaveChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Save changes?'),
      content: Text('“$title” has changes that are not saved.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, LeaveChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, LeaveChoice.discard),
          child: const Text("Don't save"),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, LeaveChoice.save),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  return choice ?? LeaveChoice.cancel;
}

/// Asks for a drawing name. Returns null when cancelled.
Future<String?> askForName(BuildContext context, String initial) =>
    showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(initial: initial),
    );

/// Asks for a shape's name. Returns null when cancelled; an empty string
/// means "use the automatic name".
Future<String?> askForShapeName(BuildContext context, String initial) =>
    showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(initial: initial, forShape: true),
    );

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial, this.forShape = false});

  final String initial;
  final bool forShape;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initial)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initial.length,
      );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _text,
      autofocus: true,
      decoration: widget.forShape
          ? const InputDecoration(
              labelText: 'Shape name',
              helperText: 'Leave blank for the automatic name',
            )
          : const InputDecoration(labelText: 'Drawing name'),
      onSubmitted: (value) => Navigator.pop(context, value),
    );
    return AlertDialog(
      title: Text(widget.forShape ? 'Rename shape' : 'Save in this browser'),
      content: SizedBox(
        width: widget.forShape ? 320 : 360,
        child: widget.forShape
            ? field
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  field,
                  const SizedBox(height: 12),
                  const Text(
                    'Drawings are kept in this browser only. They are not backed '
                    'up; use File → Export to keep a copy.',
                    style: TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: Text(widget.forShape ? 'Rename' : 'Save'),
        ),
      ],
    );
  }
}

/// What the user chose in the Open dialog.
sealed class OpenChoice {
  const OpenChoice();
}

class OpenSaved extends OpenChoice {
  const OpenSaved(this.entry);

  final LibraryEntry entry;
}

class OpenFromFile extends OpenChoice {
  const OpenFromFile();
}

/// Lists drawings saved in this browser, with an option to import a file.
Future<OpenChoice?> chooseDrawing(
  BuildContext context,
  DrawingLibrary library,
) {
  return showDialog<OpenChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Open drawing'),
      content: SizedBox(
        width: 420,
        height: 320,
        child: FutureBuilder<List<LibraryEntry>>(
          future: library.list(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('${snapshot.error}');
            }
            final entries = snapshot.data;
            if (entries == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (entries.isEmpty) {
              return const Center(
                child: Text(
                  'No drawings saved in this browser yet.',
                  style: TextStyle(color: Palette.muted),
                ),
              );
            }
            return ListView(
              children: [
                for (final entry in entries)
                  ListTile(
                    dense: true,
                    title: Text(entry.title),
                    subtitle: Text(_when(entry.savedAt)),
                    onTap: () => Navigator.pop(context, OpenSaved(entry)),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const OpenFromFile()),
          child: const Text('Import .ggnome file…'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

String _when(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Saved ${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}
