import 'package:flutter/material.dart';

import '../../domain/grow/crop.dart';
import 'commit_field.dart';

/// Blank overrides keep the crop default; unreadable ranges stay uncommitted.
class CropRangeField extends StatelessWidget {
  const CropRangeField({
    super.key,
    required this.label,
    required this.value,
    required this.fallback,
    required this.unit,
    required this.onCommitted,
  });

  final String label;
  final IntRange? value;
  final IntRange? fallback;
  final String unit;
  final ValueChanged<IntRange?> onCommitted;

  @override
  Widget build(BuildContext context) => CommitField(
    label: label,
    value: value?.toString() ?? '',
    hint: fallback == null ? '—' : '$fallback $unit',
    suffix: unit,
    commit: (text) {
      try {
        onCommitted(_parseRange(text));
        return null;
      } on FormatException catch (e) {
        return e.message;
      }
    },
  );
}

/// Spacing overrides accept decimal inches; day/week fields stay integral.
class CropLengthRangeField extends StatelessWidget {
  const CropLengthRangeField({
    super.key,
    required this.label,
    required this.value,
    required this.fallback,
    required this.onCommitted,
  });

  final String label;
  final LengthRange? value;
  final LengthRange fallback;
  final ValueChanged<LengthRange?> onCommitted;

  @override
  Widget build(BuildContext context) => CommitField(
    label: label,
    value: value?.toString() ?? '',
    hint: '$fallback in',
    suffix: 'in',
    commit: (text) {
      if (text.trim().isEmpty) {
        onCommitted(null);
        return null;
      }
      const number = r'(\d{1,4}(?:\.\d+)?|\.\d+)';
      final match = RegExp(
        '^$number\\s*(?:(?:-|–|—|to)\\s*$number)?\$',
      ).firstMatch(text.trim());
      if (match == null) return 'Enter a number or a range like 0.5–1';
      final a = num.parse(match[1]!);
      final b = match[2] == null ? a : num.parse(match[2]!);
      onCommitted(a <= b ? LengthRange(a, b) : LengthRange(b, a));
      return null;
    },
  );
}

/// Reads "5-7", "5–7", "5 to 7" or "6" as a range. Blank is null.
/// Throws [FormatException] with a message for anything else.
IntRange? _parseRange(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final match = RegExp(
    r'^(\d{1,4})\s*(?:(?:-|–|—|to)\s*(\d{1,4}))?$',
  ).firstMatch(t);
  if (match == null) {
    throw const FormatException('Enter a number or a range like 5–7');
  }
  final a = int.parse(match[1]!);
  final b = match[2] == null ? a : int.parse(match[2]!);
  return a <= b ? IntRange(a, b) : IntRange(b, a);
}
