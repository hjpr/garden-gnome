import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/editor_controller.dart';
import '../../domain/feature.dart';
import '../theme.dart';
import '../widgets/panel.dart';
import 'measure_field.dart';

/// Properties for one raised bed, greenhouse or high tunnel: its name
/// (click to rename, bin to delete), then its size and turn.
class FeatureProperties extends StatelessWidget {
  const FeatureProperties({
    super.key,
    required this.editor,
    required this.feature,
  });

  final EditorController editor;
  final Feature feature;

  @override
  Widget build(BuildContext context) {
    final units = editor.settings.units;
    final id = feature.id;
    void change(String label, Feature Function(Feature) edit) {
      final current = editor.document.featureById(id);
      if (current != null) editor.updateFeature(label, edit(current));
    }

    MeasureField length(
      String field,
      String label,
      double value,
      Feature Function(Feature, double) edit,
    ) => MeasureField(
      editor: editor,
      ownerId: id,
      field: field,
      label: label,
      unit: units.symbol,
      metres: value,
      toDisplay: units.fromMetres,
      fromDisplay: units.toMetres,
      enabled: true,
      minimum: Minimum.aboveZero,
      apply: (v) => change('Change ${label.toLowerCase()}', (f) => edit(f, v)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FeatureName(
          key: ValueKey(('name', id)),
          editor: editor,
          feature: feature,
        ),
        PropertyGroup(
          title: 'SIZE',
          children: [
            length(
              'length',
              'Length',
              feature.length,
              (f, v) => f.copyWith(length: v),
            ),
            length(
              'width',
              'Width',
              feature.width,
              (f, v) => f.copyWith(width: v),
            ),
            length(
              'height',
              'Height',
              feature.height,
              (f, v) => f.copyWith(height: v),
            ),
            MeasureField(
              editor: editor,
              ownerId: id,
              field: 'rotation',
              label: 'Rotation',
              unit: '°',
              metres: feature.rotation,
              enabled: true,
              minimum: Minimum.none,
              apply: (v) => change('Rotate', (f) => f.copyWith(rotation: v)),
            ),
            PropertyRow(
              label: 'Footprint',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  editor.settings.areaUnits.format(feature.footprint),
                  key: const ValueKey('feature-footprint'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The feature's name with a bin beside it. Clicking the name turns it
/// into a text box: Enter or clicking away saves, Esc cancels, and a blank
/// name goes back to the automatic one.
class _FeatureName extends StatefulWidget {
  const _FeatureName({super.key, required this.editor, required this.feature});

  final EditorController editor;
  final Feature feature;

  @override
  State<_FeatureName> createState() => _FeatureNameState();
}

class _FeatureNameState extends State<_FeatureName> {
  TextEditingController? _text;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _text != null) _save();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _text?.dispose();
    super.dispose();
  }

  void _start() {
    final name = widget.feature.displayName;
    setState(() {
      _text = TextEditingController(text: name)
        ..selection = TextSelection(baseOffset: 0, extentOffset: name.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _save() {
    final text = _text?.text.trim();
    setState(() {
      _text?.dispose();
      _text = null;
    });
    if (text == null) return;
    final feature = widget.feature;
    final automatic = feature.copyWith(label: () => null).displayName;
    final label = text.isEmpty || text == automatic ? null : text;
    widget.editor.updateFeature(
      'Rename ${feature.kind.label.toLowerCase()}',
      feature.copyWith(label: () => label),
    );
  }

  void _cancel() {
    setState(() {
      _text?.dispose();
      _text = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final feature = widget.feature;
    final text = _text;
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: Palette.field,
        borderRadius: BorderRadius.circular(Metrics.radius),
      ),
      child: Row(
        children: [
          AppIcon(_icon(feature.kind), size: 14, color: Palette.muted),
          const SizedBox(width: 6),
          Expanded(
            child: text != null
                ? CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape): _cancel,
                    },
                    child: TextField(
                      controller: text,
                      focusNode: _focus,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _save(),
                    ),
                  )
                : Tooltip(
                    message: 'Click to rename',
                    child: InkWell(
                      onTap: _start,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          feature.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Palette.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          IconAction(
            iconData: Icons.delete_outline,
            label: 'Delete ${feature.displayName}',
            size: 30,
            onPressed: () => widget.editor.removeFeature(feature.id),
          ),
        ],
      ),
    );
  }

  static String _icon(FeatureKind kind) => switch (kind) {
    FeatureKind.raisedBed => 'raised-bed.svg',
    FeatureKind.greenhouse => 'greenhouse.svg',
    FeatureKind.highTunnel => 'high-tunnel.svg',
  };
}
