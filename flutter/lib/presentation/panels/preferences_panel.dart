import 'package:flutter/material.dart';

import '../../application/camera.dart';
import '../../application/editor_controller.dart';
import '../../application/workspace_settings.dart';
import '../theme.dart';
import '../widgets/panel.dart';

/// Drawing styles and zoom limits. Typed values are held until Apply, and
/// kept while the panel is minimized; closing the panel discards them.
class PreferencesBody extends StatefulWidget {
  const PreferencesBody({super.key, required this.editor});

  final EditorController editor;

  @override
  State<PreferencesBody> createState() => _PreferencesBodyState();
}

class _PreferencesBodyState extends State<PreferencesBody> {
  static const _fields = {
    'lineWidth': 'Line width (px)',
    'gridThickness': 'Thickness (px)',
    'gridColor': 'Color',
    'gridOpacity': 'Opacity (%)',
    'zoomMin': 'Minimum (%)',
    'zoomMax': 'Maximum (%)',
    'history': 'Undo steps',
  };

  late final Map<String, TextEditingController> _text;
  String? _status;
  bool _statusIsError = false;

  EditorController get _editor => widget.editor;

  @override
  void initState() {
    super.initState();
    final values =
        _editor.preferencesDraft ??
        _fromAppearance(_editor.settings.appearance);
    _text = {
      for (final key in _fields.keys)
        key: TextEditingController(text: values[key]),
    };
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  static Map<String, String> _fromAppearance(Appearance a) => {
    'lineWidth': _number(a.lineWidth),
    'gridThickness': _number(a.gridThickness),
    'gridColor':
        '#${(a.gridColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
    'gridOpacity': _number(a.gridOpacity * 100),
    'zoomMin': _number(a.zoomLimits.min * 100),
    'zoomMax': _number(a.zoomLimits.max * 100),
    'history': '${a.historyCapacity}',
  };

  static String _number(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void _onChanged() {
    _editor.preferencesDraft = {
      for (final e in _text.entries) e.key: e.value.text,
    };
    _editor.draftsChanged();
    if (_status != null) setState(() => _status = null);
  }

  void _apply() {
    double? n(String key) => double.tryParse(_text[key]!.text.trim());
    final colour = RegExp(
      r'^#?([0-9a-fA-F]{6})$',
    ).firstMatch(_text['gridColor']!.text.trim());
    final history = int.tryParse(_text['history']!.text.trim());
    final values = [
      n('lineWidth'),
      n('gridThickness'),
      n('gridOpacity'),
      n('zoomMin'),
      n('zoomMax'),
    ];
    String? problem;
    if (values.contains(null) || history == null) {
      problem = 'Enter a number in every box';
    } else if (colour == null) {
      problem = 'Enter the grid color as #rrggbb';
    }
    Appearance? next;
    if (problem == null) {
      next = Appearance(
        lineWidth: values[0]!,
        gridThickness: values[1]!,
        gridOpacity: values[2]! / 100,
        gridColor: 0xFF000000 | int.parse(colour!.group(1)!, radix: 16),
        zoomLimits: ZoomLimits(min: values[3]! / 100, max: values[4]! / 100),
        historyCapacity: history!,
      );
      problem = next.problem;
    }
    if (problem != null) {
      return setState(() {
        _status = problem;
        _statusIsError = true;
      });
    }
    _editor.preferencesDraft = null;
    _editor.updateSettings(_editor.settings.copyWith(appearance: next));
    setState(() {
      _status = 'Applied';
      _statusIsError = false;
    });
  }

  Widget _field(String key) => PropertyRow(
    label: _fields[key]!,
    child: Semantics(
      label: _fields[key],
      child: TextField(
        controller: _text[key],
        style: const TextStyle(fontSize: 13),
        onChanged: (_) => _onChanged(),
        onSubmitted: (_) => _apply(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PropertyGroup(title: 'Drawing', children: [_field('lineWidth')]),
        PropertyGroup(
          title: 'Grid',
          children: [
            _field('gridThickness'),
            _field('gridColor'),
            _field('gridOpacity'),
          ],
        ),
        PropertyGroup(
          title: 'Zoom limits',
          children: [_field('zoomMin'), _field('zoomMax')],
        ),
        PropertyGroup(title: 'History', children: [_field('history')]),
        Row(
          children: [
            FilledButton(onPressed: _apply, child: const Text('Apply')),
            const SizedBox(width: 12),
            if (_status != null)
              Expanded(
                child: Text(
                  _status!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _statusIsError ? Palette.invalid : Palette.muted,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
