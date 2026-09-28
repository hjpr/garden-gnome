import 'package:flutter/material.dart';

import '../../application/camera.dart';
import '../../application/editor_controller.dart';
import '../../application/workspace_settings.dart';
import '../../domain/units.dart';
import '../theme.dart';
import '../widgets/panel.dart';

/// The groups Preferences is split into, listed down its left side.
enum PreferencesCategory {
  canvas('Canvas'),
  style('Style'),
  notifications('Notifications');

  const PreferencesCategory(this.label);

  final String label;
}

/// Preferences: categories on the left, their options on the right.
///
/// Typed values are held until Apply, across categories; closing the
/// dialog discards them. Choices from a list (menu size, toast position)
/// apply at once.
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
    'heightLowest': 'Lowest',
    'heightHighest': 'Highest',
    'history': 'Undo steps',
  };

  late final Map<String, TextEditingController> _text;
  PreferencesCategory _category = PreferencesCategory.canvas;
  String? _status;
  bool _statusIsError = false;

  EditorController get _editor => widget.editor;

  @override
  void initState() {
    super.initState();
    final values =
        _editor.preferencesDraft ??
        _fromAppearance(_editor.settings.appearance, _editor.settings.units);
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

  static Map<String, String> _fromAppearance(Appearance a, Units units) => {
    'lineWidth': _number(a.lineWidth),
    'gridThickness': _number(a.gridThickness),
    'gridColor':
        '#${(a.gridColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
    'gridOpacity': _number(a.gridOpacity * 100),
    'heightLowest': _length(a.heightLimits.lowest, units),
    'heightHighest': _length(a.heightLimits.highest, units),
    'history': '${a.historyCapacity}',
  };

  static String _number(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// [metres] in [units], to three places at most: 5 ft converted to
  /// metres and back is not quite 5.
  static String _length(double metres, Units units) => units
      .fromMetres(metres)
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'\.?0+$'), '');

  void _onChanged() {
    _editor.preferencesDraft = {
      for (final e in _text.entries) e.key: e.value.text,
    };
    _editor.draftsChanged();
    // Apply lights up once something has been typed.
    setState(() => _status = null);
  }

  void _apply() {
    double? n(String key) => double.tryParse(_text[key]!.text.trim());
    final colour = RegExp(
      r'^#?([0-9a-fA-F]{6})$',
    ).firstMatch(_text['gridColor']!.text.trim());
    final history = int.tryParse(_text['history']!.text.trim());
    final units = _editor.settings.units;
    final values = [
      n('lineWidth'),
      n('gridThickness'),
      n('gridOpacity'),
      n('heightLowest'),
      n('heightHighest'),
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
        heightLimits: HeightLimits(
          lowest: units.toMetres(values[3]!),
          highest: units.toMetres(values[4]!),
        ),
        historyCapacity: history!,
        toastPosition: _editor.settings.appearance.toastPosition,
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

  Widget _field(String key) {
    final label = switch (key) {
      'heightLowest' ||
      'heightHighest' => '${_fields[key]} (${_editor.settings.units.symbol})',
      _ => _fields[key]!,
    };
    return PropertyRow(
      label: label,
      child: Semantics(
        label: label,
        child: TextField(
          controller: _text[key],
          style: const TextStyle(fontSize: 13),
          onChanged: (_) => _onChanged(),
          onSubmitted: (_) => _apply(),
        ),
      ),
    );
  }

  List<Widget> _options(PreferencesCategory category) {
    final s = _editor.settings;
    return switch (category) {
      PreferencesCategory.canvas => [
        PropertyGroup(
          title: 'CAMERA HEIGHT',
          children: [_field('heightLowest'), _field('heightHighest')],
        ),
        PropertyGroup(title: 'HISTORY', children: [_field('history')]),
        PropertyGroup(
          title: 'VIEWPORT',
          children: [
            PropertyRow(
              label: 'Menu size',
              child: CompactDropdown<MenuScale>(
                label: 'Menu size',
                value: s.menuScale,
                items: {for (final m in MenuScale.values) m: m.label},
                onChanged: (m) {
                  _editor.updateSettings(s.copyWith(menuScale: m));
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ],
      PreferencesCategory.style => [
        PropertyGroup(title: 'DRAWING', children: [_field('lineWidth')]),
        PropertyGroup(
          title: 'GRID',
          children: [
            _field('gridThickness'),
            _field('gridColor'),
            _field('gridOpacity'),
          ],
        ),
      ],
      PreferencesCategory.notifications => [
        PropertyGroup(
          title: 'TOASTS',
          children: [
            PropertyRow(
              label: 'Position',
              child: CompactDropdown<ToastPosition>(
                label: 'Toast position',
                value: s.appearance.toastPosition,
                items: {for (final p in ToastPosition.values) p: p.label},
                onChanged: (p) {
                  _editor.updateSettings(
                    s.copyWith(appearance: s.appearance.withToastPosition(p)),
                  );
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ],
    };
  }

  Widget _categoryButton(PreferencesCategory category) {
    final selected = category == _category;
    final colour = selected ? Palette.accent : Palette.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: category.label,
        child: Material(
          color: selected ? Palette.wash : Colors.transparent,
          borderRadius: BorderRadius.circular(Metrics.radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(Metrics.radius),
            hoverColor: Palette.hover,
            onTap: () => setState(() => _category = category),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      category.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colour,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _editor.preferencesPending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 168,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final c in PreferencesCategory.values)
                      _categoryButton(c),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: VerticalDivider(width: 1),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    key: ValueKey(_category),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _options(_category),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                _status ?? '',
                style: TextStyle(
                  fontSize: 12,
                  color: _statusIsError ? Palette.invalid : Palette.muted,
                ),
              ),
            ),
            FilledButton(
              onPressed: pending ? _apply : null,
              child: const Text('Apply'),
            ),
          ],
        ),
      ],
    );
  }
}
