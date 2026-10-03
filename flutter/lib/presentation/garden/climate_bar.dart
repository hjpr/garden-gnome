import 'package:flutter/material.dart';

import '../../application/garden_controller.dart';
import '../../domain/grow/climate.dart';
import '../../domain/grow/day.dart';
import '../widgets/property_controls.dart';
import 'commit_field.dart';
import 'garden_card.dart';

/// Hardiness zone and frost dates, the inputs to every planting window.
/// A blank frost box uses the zone's typical date, shown greyed.
class ClimateBar extends StatelessWidget {
  const ClimateBar({super.key, required this.garden});

  final GardenController garden;

  @override
  Widget build(BuildContext context) {
    final climate = garden.climate;
    Widget frost(
      String label,
      MonthDay? own,
      MonthDay zoneDefault,
      void Function(MonthDay?) set,
    ) => SizedBox(
      width: 230,
      child: PropertyRow(
        label: label,
        child: CommitField(
          label: label,
          value: own?.toString() ?? '',
          hint: zoneDefault.toString(),
          commit: (t) {
            if (t.trim().isEmpty) {
              set(null);
              return null;
            }
            final day = parseMonthDay(t);
            if (day == null) return 'e.g. Apr 20';
            set(day);
            return null;
          },
        ),
      ),
    );
    return GardenCard(
      fill: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 24,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 200,
            child: PropertyRow(
              label: 'Hardiness',
              child: CompactDropdown<HardinessZone>(
                label: 'Hardiness zone',
                value: climate.zone,
                items: {for (final z in HardinessZone.all) z: 'Zone ${z.code}'},
                onChanged: garden.setZone,
              ),
            ),
          ),
          frost(
            'Last frost',
            climate.lastSpringFrost,
            climate.zone.lastSpringFrost,
            (d) => garden.setFrostDates(lastSpring: () => d),
          ),
          frost(
            'First frost',
            climate.firstFallFrost,
            climate.zone.firstFallFrost,
            (d) => garden.setFrostDates(firstFall: () => d),
          ),
        ],
      ),
    );
  }
}

/// Reads "Apr 20", "april 20", "4/20" or "04-20". Null when unreadable.
MonthDay? parseMonthDay(String text) {
  final t = text.trim().toLowerCase();
  final numeric = RegExp(r'^(\d{1,2})\s*[/\-.]\s*(\d{1,2})$').firstMatch(t);
  if (numeric != null) {
    return MonthDay.tryParse('${numeric[1]}-${numeric[2]}');
  }
  final named = RegExp(r'^([a-z]{3})[a-z]*\.?\s+(\d{1,2})$').firstMatch(t);
  if (named == null) return null;
  const months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun', //
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];
  final m = months.indexOf(named[1]!);
  if (m < 0) return null;
  return MonthDay.tryParse('${m + 1}-${named[2]}');
}
