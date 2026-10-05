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
    Widget fact(String label, String value, String field) =>
        _fact(label, value, estimated: crop.estimated.contains(field));
    return _NotesCard(
      title: '${crop.name} growing notes',
      facts: [
        fact('Season', crop.season.label, 'season'),
        fact('Frost', crop.frostTolerance.label, 'frostTolerance'),
        fact('Sowing', crop.sowing.label, 'sowing'),
        fact('Maturity', '${crop.daysToMaturity} days', 'daysToMaturity'),
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
        fact('Plant out', _frostWeeks(crop.plantOutWeeks), 'plantOutWeeks'),
        if (crop.soilTempF != null)
          fact('Soil', '${crop.soilTempF} °F', 'soilTempF'),
      ],
      estimated: crop.estimated.isNotEmpty,
      sections: crop.sections,
      url: crop.url,
    );
  }
}

/// A cover crop's row of Johnny's comparison chart, then its growing
/// notes page when it has one.
class CoverCropNotes extends StatelessWidget {
  const CoverCropNotes({super.key, required this.crop});

  final CoverCrop crop;

  @override
  Widget build(BuildContext context) {
    final zone = int.tryParse(crop.hardinessZone) != null
        ? 'Zone ${crop.hardinessZone}'
        : crop.hardinessZone[0].toUpperCase() + crop.hardinessZone.substring(1);
    return _NotesCard(
      title: '${crop.name} growing notes',
      facts: [
        _fact(
          'Sow',
          crop.frostSeeding
              ? '${crop.sowingSeason} · frost seeding'
              : crop.sowingSeason,
        ),
        _fact('Germ. min', '${crop.minGermTempF} °F'),
        _fact('Hardiness', zone),
        _fact('Growth', crop.growthRate),
        _fact('Per 1,000 sq ft', crop.seedPer1000SqFt),
        _fact('Per acre', crop.seedPerAcre),
        _fact('Depth', crop.sowingDepth),
      ],
      benefits: [
        for (final b in crop.benefits)
          b.secondYear ? '${b.name} (2nd year)' : b.name,
      ],
      sections: crop.sections,
      url: crop.url,
    );
  }
}

Widget _fact(String label, String value, {bool estimated = false}) => Padding(
  padding: const EdgeInsets.only(right: 18, bottom: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: sectionTitleStyle),
      Tooltip(
        message: estimated ? 'Estimated' : '',
        child: Text(
          estimated ? '$value*' : value,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    ],
  ),
);

/// Facts across the top, then the catalog's sections and source link.
class _NotesCard extends StatelessWidget {
  const _NotesCard({
    required this.title,
    required this.facts,
    required this.sections,
    this.benefits = const [],
    this.estimated = false,
    this.url,
  });

  final String title;
  final List<Widget> facts;
  final List<String> benefits;
  final bool estimated;
  final List<CropSection> sections;
  final String? url;

  @override
  Widget build(BuildContext context) => GardenCard(
    title: title,
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(children: facts),
          if (estimated)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '* Estimated',
                style: TextStyle(fontSize: 11.5, color: Palette.faint),
              ),
            ),
          if (benefits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('BENEFITS', style: sectionTitleStyle),
                  const SizedBox(height: 2),
                  Text(
                    benefits.join(' · '),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          const Divider(),
          for (final s in sections)
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
          if (url != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SelectableText(
                'Source: $url',
                style: const TextStyle(fontSize: 11.5, color: Palette.faint),
              ),
            ),
        ],
      ),
    ),
  );
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
