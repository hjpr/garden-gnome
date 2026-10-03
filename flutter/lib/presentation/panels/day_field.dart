import 'package:flutter/material.dart';

import '../../domain/grow/day.dart';
import '../theme.dart';

/// A calendar day in Properties. Shows the date (or a greyed dash);
/// clicking it opens a calendar, and the day clicked is stored. With
/// [onCleared], a set date has a small × to clear it.
class DayField extends StatelessWidget {
  const DayField({
    super.key,
    required this.label,
    required this.day,
    required this.enabled,
    required this.onChanged,
    this.onCleared,
    this.first,
  });

  final String label;
  final DateTime? day;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback? onCleared;

  /// The earliest day the calendar offers, e.g. Sown for Transplanted.
  final DateTime? first;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    DateTime local(DateTime d) => DateTime(d.year, d.month, d.day);
    final firstDate = first == null ? DateTime(now.year - 10) : local(first!);
    var initial = local(day ?? now);
    if (initial.isBefore(firstDate)) initial = firstDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 10),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: label.toUpperCase(),
    );
    if (picked != null) onChanged(dayOf(picked));
  }

  @override
  Widget build(BuildContext context) {
    final text = day == null ? '—' : '${formatDay(day!)}, ${day!.year}';
    final clearable = enabled && day != null && onCleared != null;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            enabled: enabled,
            label: '$label, $text',
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('day-$label'),
              onTap: enabled ? () => _pick(context) : null,
              borderRadius: BorderRadius.circular(Metrics.radius),
              hoverColor: Palette.hover,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: Palette.field,
                  borderRadius: BorderRadius.circular(Metrics.radius),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        text,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: enabled && day != null
                              ? Palette.ink
                              : Palette.faint,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: enabled ? Palette.muted : Palette.faint,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (clearable)
          IconButton(
            tooltip: 'Clear $label',
            visualDensity: VisualDensity.compact,
            iconSize: 14,
            onPressed: onCleared,
            icon: const Icon(Icons.close, color: Palette.muted),
          ),
      ],
    );
  }
}
