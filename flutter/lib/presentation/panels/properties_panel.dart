import 'package:flutter/material.dart';

import '../../application/drafts.dart';
import '../../application/editor_controller.dart';
import '../../domain/fill_patterns.dart';
import '../../domain/land_rules.dart';
import '../../domain/layer.dart';
import '../theme.dart';
import '../widgets/draft_text_field.dart';
import '../widgets/panel.dart';
import 'reference_properties.dart';

/// Settings for the selected layer: its name, status, and options.
class PropertiesBody extends StatelessWidget {
  const PropertiesBody({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    if (editor.showsReference) {
      return ReferenceProperties(
        key: const ValueKey('reference-properties'),
        editor: editor,
      );
    }
    final layer = editor.selectedLayer;
    if (layer == null) {
      return const EmptyPanelText('Nothing selected.');
    }
    final document = editor.document;
    final invalid = !document.isValid(layer.id);
    final reason = document.inactiveReason(layer.id);
    final status = invalid
        ? 'Invalid: $reason'
        : (reason == null ? 'Active' : 'Inactive: $reason');
    // A locked layer's details are shown read-only.
    final lockNotice = editor.lockNotice(layer.id);
    final editable = lockNotice == null;
    return Column(
      key: ValueKey(layer.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NameEditor(editor: editor, layer: layer, editable: editable),
        _StatusBadge(
          text: status,
          colour: invalid
              ? Palette.invalid
              : (reason == null ? Palette.valid : Palette.muted),
        ),
        PropertyRow(
          label: 'Net area',
          child: Text(
            editor.settings.areaUnits.format(
              document.geometryOf(layer.id).area,
            ),
            key: const ValueKey('net-area'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (lockNotice != null)
          _LockedNote(
            text: lockNotice,
            onUnlock: layer.locked
                ? () => editor.setLayerLocked(layer.id, false)
                : null,
          ),
        ...switch (layer.properties) {
          FieldProperties p => _fieldOptions(layer, p, editable),
          PlotProperties p => _plotOptions(layer, p, editable),
          AreaProperties p => _areaOptions(layer, p, editable),
        },
        PropertyGroup(title: 'LOOK', children: [_patternRow(layer, editable)]),
      ],
    );
  }

  List<Widget> _fieldOptions(Layer layer, FieldProperties p, bool editable) => [
    PropertyGroup(
      title: 'OPTIONS',
      children: [
        _colorRow(
          layer,
          p.color,
          OutlineColor.fieldChoices,
          (c) => p.copyWith(color: c),
          editable,
        ),
        PropertyRow(
          label: 'Soil drainage',
          child: CompactDropdown<SoilDrainage?>(
            label: 'Soil drainage',
            value: p.drainage,
            items: {
              null: 'Select…',
              for (final d in SoilDrainage.values) d: d.label,
            },
            onChanged: editable
                ? (d) => editor.updateProperties(
                    layer.id,
                    p.copyWith(drainage: () => d),
                  )
                : null,
          ),
        ),
      ],
    ),
    PropertyGroup(
      title: 'SOIL SAMPLE',
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text(
            'Lab values as recorded. Units and method unspecified.',
            style: TextStyle(fontSize: 11.5, color: Palette.muted),
          ),
        ),
        for (final (field, label) in SoilSample.fields)
          _soilRow(layer, p, field, label, editable),
      ],
    ),
  ];

  /// One soil value. Blank clears it; anything else must be a finite
  /// number. Values are stored as typed, with no unit conversion.
  Widget _soilRow(
    Layer layer,
    FieldProperties p,
    String field,
    String label,
    bool editable,
  ) => PropertyRow(
    label: label,
    child: DraftTextField(
      editor: editor,
      draftKey: '${layer.id}/soil/$field',
      layerId: layer.id,
      committedText: _formatSoil(p.soil.valueOf(field)),
      label: label,
      enabled: editable,
      check: _soilProblem,
      apply: (text) {
        final current = editor.document.layers[layer.id]?.properties;
        if (current is! FieldProperties) return;
        final value = _parseSoil(text);
        if (value == current.soil.valueOf(field)) return;
        editor.updateProperties(
          layer.id,
          current.copyWith(soil: current.soil.withValue(field, value)),
        );
      },
    ),
  );

  static String _formatSoil(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  static double? _parseSoil(String text) =>
      text.trim().isEmpty ? null : double.tryParse(text.trim());

  static String? _soilProblem(String text) {
    if (text.trim().isEmpty) return null;
    final value = double.tryParse(text.trim());
    return value == null || !value.isFinite
        ? 'Enter a number or leave blank'
        : null;
  }

  List<Widget> _plotOptions(Layer layer, PlotProperties p, bool editable) => [
    PropertyGroup(
      title: 'OPTIONS',
      children: [
        _colorRow(
          layer,
          p.color,
          OutlineColor.plotChoices,
          (c) => p.copyWith(color: c),
          editable,
        ),
        PropertyRow(
          label: 'Ground',
          child: DraftTextField(
            editor: editor,
            draftKey: '${layer.id}/ground',
            layerId: layer.id,
            committedText: p.ground ?? '',
            label: 'Ground',
            hint: 'e.g. raised beds',
            enabled: editable,
            apply: (text) {
              final current = editor.document.layers[layer.id]?.properties;
              if (current is! PlotProperties) return;
              final value = text.trim().isEmpty ? null : text.trim();
              if (value == current.ground) return;
              editor.updateProperties(
                layer.id,
                current.copyWith(ground: () => value),
              );
            },
          ),
        ),
      ],
    ),
  ];

  List<Widget> _areaOptions(Layer layer, AreaProperties p, bool editable) => [
    PropertyGroup(
      title: 'OPTIONS',
      children: [
        const PropertyRow(
          label: 'Planting type',
          child: Text('Flat', style: TextStyle(fontSize: 13)),
        ),
        PropertyRow(
          label: 'Crop',
          child: DraftTextField(
            editor: editor,
            draftKey: '${layer.id}/crop',
            layerId: layer.id,
            committedText: p.crop ?? '',
            label: 'Crop',
            hint: 'e.g. tomatoes',
            enabled: editable,
            apply: (text) {
              final current = editor.document.layers[layer.id]?.properties;
              if (current is! AreaProperties) return;
              final value = text.trim().isEmpty ? null : text.trim();
              if (value == current.crop) return;
              editor.updateProperties(
                layer.id,
                current.copyWith(crop: () => value),
              );
            },
          ),
        ),
      ],
    ),
  ];

  /// The same pattern the Pattern tool sets. It needs a closed boundary.
  Widget _patternRow(Layer layer, bool editable) {
    final document = editor.document;
    final closed = document.geometryOf(layer.id).isClosed;
    return PropertyRow(
      label: 'Pattern',
      child: CompactDropdown<FillPattern?>(
        label: 'Pattern',
        value: document.storedPatternOf(layer.id),
        items: {null: 'None', for (final f in FillPattern.values) f: f.label},
        onChanged: editable && closed
            ? (f) => editor.setPattern(layer.id, f)
            : null,
      ),
    );
  }

  Widget _colorRow(
    Layer layer,
    OutlineColor value,
    List<OutlineColor> choices,
    LayerProperties Function(OutlineColor) change,
    bool editable,
  ) => PropertyRow(
    label: 'Color',
    child: CompactDropdown<OutlineColor>(
      label: 'Color',
      value: value,
      items: {for (final c in choices) c: c.label},
      onChanged: editable
          ? (c) {
              if (c != value) editor.updateProperties(layer.id, change(c));
            }
          : null,
    ),
  );
}

/// A small dot and label showing whether the layer counts as land.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.text, required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 6),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
        ),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: colour)),
        ),
      ],
    ),
  );
}

/// A quiet note that the layer is locked, with a shortcut to unlock it
/// when the lock is on this layer (not on one around it).
class _LockedNote extends StatelessWidget {
  const _LockedNote({required this.text, this.onUnlock});

  final String text;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 4, bottom: 2),
    padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
    decoration: BoxDecoration(
      color: Palette.field,
      borderRadius: BorderRadius.circular(Metrics.radius),
    ),
    child: Row(
      children: [
        const Icon(Icons.lock_outline, size: 14, color: Palette.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            onUnlock == null ? text : 'Locked. Changes are turned off',
            style: const TextStyle(fontSize: 12, color: Palette.muted),
          ),
        ),
        if (onUnlock != null)
          TextButton(onPressed: onUnlock, child: const Text('Unlock')),
      ],
    ),
  );
}

/// The layer name, with a Rename form that saves only on Save name.
class _NameEditor extends StatefulWidget {
  const _NameEditor({
    required this.editor,
    required this.layer,
    required this.editable,
  });

  final EditorController editor;
  final Layer layer;
  final bool editable;

  @override
  State<_NameEditor> createState() => _NameEditorState();
}

class _NameEditorState extends State<_NameEditor> {
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
              FilledButton(onPressed: _save, child: const Text('Save name')),
              const SizedBox(width: 8),
              TextButton(onPressed: _stop, child: const Text('Cancel')),
            ],
          ),
        ],
      ),
    );
  }
}
