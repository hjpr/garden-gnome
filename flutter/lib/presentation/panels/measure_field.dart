import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../widgets/draft_text_field.dart';
import '../widgets/panel.dart';

/// The smallest value a [MeasureField] accepts.
enum Minimum { none, zero, aboveZero }

/// One labelled number in Properties, such as a row width or a feature's
/// length. Shown in the user's units ([toDisplay]) with the unit in the
/// label, stored in metres ([fromDisplay]). Enter or leaving the box
/// applies it; Esc puts the stored value back.
class MeasureField extends StatelessWidget {
  const MeasureField({
    super.key,
    required this.editor,
    required this.ownerId,
    required this.field,
    required this.label,
    required this.unit,
    required this.metres,
    required this.enabled,
    required this.minimum,
    required this.apply,
    this.toDisplay = _same,
    this.fromDisplay = _same,
    this.step,
    this.bigStep,
  });

  final EditorController editor;

  /// The layer or feature the value belongs to, so a draft is never
  /// applied to another one.
  final String ownerId;
  final String field;
  final String label;
  final String unit;

  /// The stored value (metres for lengths, degrees for angles).
  final double metres;
  final bool enabled;
  final Minimum minimum;
  final ValueChanged<double> apply;
  final double Function(double) toDisplay;
  final double Function(double) fromDisplay;

  /// When set, up and down arrows (and the Up and Down keys) change the
  /// shown value by this much, or by [bigStep] with Shift held.
  final double? step;
  final double? bigStep;

  static double _same(double value) => value;

  @override
  Widget build(BuildContext context) => PropertyRow(
    label: '$label ($unit)',
    child: DraftTextField(
      // Re-keyed when the units change, so stale typing is dropped.
      key: ValueKey(('measure', ownerId, field, unit)),
      editor: editor,
      draftKey: '$ownerId/$field',
      layerId: ownerId,
      committedText: format(toDisplay(metres)),
      label: label,
      enabled: enabled,
      check: _problem,
      apply: (text) {
        final value = fromDisplay(double.parse(text.trim()));
        if (value != metres) apply(value);
      },
      onStep: step == null ? null : _step,
    ),
  );

  /// One arrow step from the number in the box (typed or stored).
  void _step(String text, int direction, {required bool big}) {
    final typed = double.tryParse(text.trim());
    final shown = typed != null && typed.isFinite ? typed : toDisplay(metres);
    final by = (big ? bigStep ?? step! : step!) * direction;
    var next = shown + by;
    if (minimum == Minimum.aboveZero && next <= 0) return;
    if (minimum == Minimum.zero && next < 0) next = 0;
    final value = fromDisplay(next);
    if (value != metres) apply(value);
  }

  String? _problem(String text) {
    final value = double.tryParse(text.trim());
    if (value == null || !value.isFinite) return 'Enter a number';
    return switch (minimum) {
      Minimum.aboveZero when value <= 0 => 'Enter a number above zero',
      Minimum.zero when value < 0 => 'Enter zero or more',
      _ => null,
    };
  }

  /// Up to three decimals, with trailing zeros dropped.
  static String format(double value) =>
      value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
}
