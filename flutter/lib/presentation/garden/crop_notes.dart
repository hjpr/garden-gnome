import 'package:flutter/material.dart';

import '../../domain/grow/crop.dart';
import '../theme.dart';
import 'garden_card.dart';

/// The crop's growing instructions from the catalog.
class CropNotes extends StatelessWidget {
  const CropNotes({super.key, required this.crop});

  final Crop crop;

  @override
  Widget build(BuildContext context) {
    String? mark(String field) =>
        crop.estimated.contains(field) ? 'Estimated' : null;
    Widget fact(String label, String value, [String? field]) => Padding(
      padding: const EdgeInsets.only(right: 18, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: sectionTitleStyle),
          Tooltip(
            message: field == null ? '' : (mark(field) ?? ''),
            child: Text(
              field != null && mark(field) != null ? '$value*' : value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
    return GardenCard(
      title: '${crop.name} growing notes',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              children: [
                fact('Season', crop.season.label, 'season'),
                fact('Frost', crop.frostTolerance.label, 'frostTolerance'),
                fact('Sowing', crop.sowing.label, 'sowing'),
                fact(
                  'Maturity',
                  '${crop.daysToMaturity} days',
                  'daysToMaturity',
                ),
                if (crop.germinationDays != null)
                  fact(
                    'Germination',
                    '${crop.germinationDays} days',
                    'germinationDays',
                  ),
                if (crop.weeksToTransplant != null)
                  fact(
                    'In trays',
                    '${crop.weeksToTransplant} weeks',
                    'weeksToTransplant',
                  ),
                fact(
                  'Plant out',
                  _frostWeeks(crop.plantOutWeeks),
                  'plantOutWeeks',
                ),
                if (crop.soilTempF != null)
                  fact('Soil', '${crop.soilTempF} °F', 'soilTempF'),
              ],
            ),
            if (crop.estimated.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '* Estimated',
                  style: TextStyle(fontSize: 11.5, color: Palette.faint),
                ),
              ),
            const Divider(),
            for (final s in crop.sections)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title.toUpperCase(), style: sectionTitleStyle),
                    const SizedBox(height: 2),
                    SelectableText(
                      s.text,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            if (crop.url != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: SelectableText(
                  'Source: ${crop.url}',
                  style: const TextStyle(fontSize: 11.5, color: Palette.faint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "2 weeks before frost – 1 week after" style text for a frost-relative
/// window.
String _frostWeeks(IntRange weeks) {
  String one(int w) =>
      w == 0 ? 'at last frost' : '${w.abs()} wk ${w < 0 ? 'before' : 'after'}';
  return weeks.min == weeks.max
      ? one(weeks.min)
      : '${one(weeks.min)} – ${one(weeks.max)}';
}
