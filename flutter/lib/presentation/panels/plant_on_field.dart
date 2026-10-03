import 'package:flutter/material.dart';

import '../../domain/grow/day.dart';
import '../theme.dart';

/// The day a planting goes in the ground. Shows the date (or a greyed
/// dash); clicking it opens a calendar, and the day clicked is stored.
class PlantOnField extends StatelessWidget {
  const PlantOnField({
    super.key,
    required this.day,
    required this.enabled,
    required this.onChanged,
  });

  final DateTime? day;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = day ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'PLANT ON',
    );
    if (picked != null) onChanged(dayOf(picked));
  }

  @override
  Widget build(BuildContext context) {
    final text = day == null ? '—' : '${formatDay(day!)}, ${day!.year}';
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Plant on, $text',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('plant-on'),
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
                    color: enabled && day != null ? Palette.ink : Palette.faint,
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
    );
  }
}
