import 'package:flutter/material.dart';

import '../../application/drafts.dart';
import '../../application/editor_controller.dart';
import '../../domain/layer.dart';
import '../widgets/icon_controls.dart';
import '../widgets/property_controls.dart';

/// The layer name, with a Rename form that saves only on Save name.
class LayerNameEditor extends StatefulWidget {
  const LayerNameEditor({
    super.key,
    required this.editor,
    required this.layer,
    required this.editable,
  });

  final EditorController editor;
  final Layer layer;
  final bool editable;

  @override
  State<LayerNameEditor> createState() => _LayerNameEditorState();
}

class _LayerNameEditorState extends State<LayerNameEditor> {
  static const _draftKey = 'rename';
  TextEditingController? _text;
  String? _error;

  bool get _renaming => _text != null;

  void _start() {
    setState(() {
      _text = TextEditingController(text: widget.layer.name);
      _error = null;
    });
  }

  void _stop() {
    widget.editor.drafts.discard(_draftKey);
    widget.editor.draftsChanged();
    setState(() {
      _text?.dispose();
      _text = null;
      _error = null;
    });
  }

  void _save() {
    try {
      final name = validLayerName(_text!.text);
      widget.editor.drafts.discard(_draftKey);
      widget.editor.renameLayer(widget.layer.id, name);
      _stop();
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  /// Records the typed name so Save and layer switching know a rename is
  /// pending. It is only ever applied by Save name.
  void _onChanged(String text) {
    widget.editor.drafts.update(
      _draftKey,
      PropertyDraft(
        layerId: widget.layer.id,
        text: text,
        committedText: widget.layer.name,
        check: _nameProblem,
        apply: (_) {},
        isRename: true,
      ),
    );
    widget.editor.draftsChanged();
  }

  static String? _nameProblem(String text) {
    try {
      validLayerName(text);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  @override
  void dispose() {
    _text?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A layer switch or Save may have dropped the pending rename.
    if (_renaming &&
        widget.editor.drafts[_draftKey] == null &&
        _text!.text != widget.layer.name) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _renaming) _stop();
      });
    }
    if (!_renaming) {
      return Row(
        children: [
          Expanded(
            child: Text(
              widget.layer.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          IconAction(
            icon: 'rename.svg',
            label: 'Rename layer',
            onPressed: widget.editable ? _start : null,
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Layer name',
              errorText: _error,
            ),
            onChanged: _onChanged,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(
                child: FilledButton(
                  onPressed: _save,
                  child: const Text(
                    'Save name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: TextButton(
                  onPressed: _stop,
                  child: const Text(
                    'Cancel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LayerColorField extends StatelessWidget {
  const LayerColorField({
    super.key,
    required this.editor,
    required this.layer,
    required this.value,
    required this.choices,
    required this.change,
    required this.enabled,
  });

  final EditorController editor;
  final Layer layer;
  final OutlineColor value;
  final List<OutlineColor> choices;
  final LayerProperties Function(OutlineColor) change;
  final bool enabled;

  @override
  Widget build(BuildContext context) => PropertyRow(
    label: 'Color',
    child: CompactDropdown<OutlineColor>(
      label: 'Color',
      value: value,
      items: {for (final c in choices) c: c.label},
      onChanged: enabled
          ? (c) {
              if (c != value) editor.updateProperties(layer.id, change(c));
            }
          : null,
    ),
  );
}
