import 'package:flutter/material.dart';

import '../../application/garden_controller.dart';
import '../../domain/grow/crop.dart';
import '../../domain/grow/variety.dart';
import '../theme.dart';
import '../widgets/property_controls.dart';
import 'commit_field.dart';
import 'crop_notes.dart';
import 'crop_range_field.dart';
import 'garden_card.dart';

/// The selected variety: its own details on the left, its crop's growing
/// notes from the catalog on the right. A cover crop has no GROWING
/// overrides: it is never planned on the calendars.
class VarietyDetail extends StatelessWidget {
  const VarietyDetail({super.key, required this.garden, required this.profile})
    : variety = null,
      cover = null;

  const VarietyDetail.cover({
    super.key,
    required this.garden,
    required Variety this.variety,
    required CoverCrop this.cover,
  }) : profile = null;

  final GardenController garden;
  final VarietyProfile? profile;
  final Variety? variety;
  final CoverCrop? cover;

  Variety get _v => profile?.variety ?? variety!;

  void _update(Variety next) => garden.updateVariety(next);

  /// A range box whose blank value falls back to the crop's.
  Widget _range(
    String label,
    IntRange? own,
    IntRange? fallback,
    String unit,
    Variety Function(IntRange?) apply,
  ) => PropertyRow(
    label: label,
    child: CropRangeField(
      label: label,
      value: own,
      fallback: fallback,
      unit: unit,
      onCommitted: (range) => _update(apply(range)),
    ),
  );

  Widget _lengthRange(
    String label,
    LengthRange? own,
    LengthRange fallback,
    Variety Function(LengthRange?) apply,
  ) => PropertyRow(
    label: label,
    child: CropLengthRangeField(
      label: label,
      value: own,
      fallback: fallback,
      onCommitted: (range) => _update(apply(range)),
    ),
  );

  Widget _text(String label, String? value, Variety Function(String?) apply) =>
      PropertyRow(
        label: label,
        child: CommitField(
          label: label,
          value: value ?? '',
          commit: (t) {
            _update(apply(t.trim().isEmpty ? null : t.trim()));
            return null;
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final crop = profile?.crop;
    final cropLine = crop != null
        ? [crop.name, ?crop.scientificName].join(' · ')
        : '${cover!.name} · ${CoverCrop.category}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 380,
          child: GardenCard(
            title: 'Variety',
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CommitField(
                    label: 'Variety name',
                    value: _v.name,
                    commit: (t) {
                      if (t.trim().isEmpty) return 'Enter a name';
                      _update(_v.copyWith(name: t.trim()));
                      return null;
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cropLine,
                    style: const TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                  _seed(),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ReorderButton(garden: garden, variety: _v),
                  ),
                  if (crop != null) _growing(crop),
                  PropertyGroup(
                    title: 'NOTES',
                    children: [
                      CommitField(
                        label: 'Notes',
                        value: _v.notes,
                        maxLines: 5,
                        commit: (t) {
                          _update(_v.copyWith(notes: t));
                          return null;
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: crop != null
              ? CropNotes(crop: crop)
              : CoverCropNotes(crop: cover!),
        ),
      ],
    );
  }

  Widget _seed() => PropertyGroup(
    title: 'SEED',
    children: [
      _text('Source', _v.source, (s) => _v.copyWith(source: () => s)),
      _text(
        'Product code',
        _v.productCode,
        (s) => _v.copyWith(productCode: () => s),
      ),
      _text(
        'On hand',
        _v.seedsOnHand,
        (s) => _v.copyWith(seedsOnHand: () => s),
      ),
      PropertyRow(
        label: 'Year packed',
        child: CommitField(
          label: 'Year packed',
          value: _v.yearPacked?.toString() ?? '',
          commit: (t) {
            if (t.trim().isEmpty) {
              _update(_v.copyWith(yearPacked: () => null));
              return null;
            }
            final y = int.tryParse(t.trim());
            if (y == null || y < 1900 || y > 2200) {
              return 'Enter a year';
            }
            _update(_v.copyWith(yearPacked: () => y));
            return null;
          },
        ),
      ),
      PropertyRow(
        label: 'Organic',
        child: Align(
          alignment: Alignment.centerLeft,
          child: Transform.scale(
            scale: 0.75,
            child: Switch(
              value: _v.organic,
              onChanged: (on) => _update(_v.copyWith(organic: on)),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _growing(Crop crop) => PropertyGroup(
    title: 'GROWING',
    children: [
      PropertyRow(
        label: 'Sowing',
        child: CompactDropdown<SowingMethod?>(
          label: 'Sowing',
          value: _v.sowing,
          items: {
            null: 'Default (${crop.sowing.label})',
            for (final s in SowingMethod.values) s: s.label,
          },
          onChanged: (s) => _update(_v.copyWith(sowing: () => s)),
        ),
      ),
      _range(
        'Maturity',
        _v.daysToMaturity,
        crop.daysToMaturity,
        'days',
        (r) => _v.copyWith(daysToMaturity: () => r),
      ),
      _range(
        'Germination',
        _v.germinationDays,
        crop.germinationDays,
        'days',
        (r) => _v.copyWith(germinationDays: () => r),
      ),
      _range(
        'In trays',
        _v.weeksToTransplant,
        crop.weeksToTransplant ?? profile!.weeksToTransplant,
        'weeks',
        (r) => _v.copyWith(weeksToTransplant: () => r),
      ),
      _lengthRange(
        'In-row',
        _v.inRowSpacingIn,
        crop.inRowSpacingIn,
        (r) => _v.copyWith(inRowSpacingIn: () => r),
      ),
      _lengthRange(
        'Between rows',
        _v.betweenRowSpacingIn,
        crop.betweenRowSpacingIn,
        (r) => _v.copyWith(betweenRowSpacingIn: () => r),
      ),
      _range(
        'Picking',
        _v.harvestWindowDays,
        crop.harvestWindowDays,
        'days',
        (r) => _v.copyWith(harvestWindowDays: () => r),
      ),
    ],
  );
}

/// Opens the variety's Johnny's product page to buy more. Greyed when
/// the catalog does not list the variety (e.g. renamed, or from another
/// seller).
class ReorderButton extends StatelessWidget {
  const ReorderButton({super.key, required this.garden, required this.variety});

  static const label = "Reorder from Johnny's";

  final GardenController garden;
  final Variety variety;

  @override
  Widget build(BuildContext context) {
    final url = garden.reorderUrlOf(variety);
    return Tooltip(
      message: url ?? "Not in Johnny's catalog",
      waitDuration: const Duration(milliseconds: 500),
      child: OutlinedButton.icon(
        onPressed: url == null ? null : () => garden.reorder(variety),
        icon: const Icon(Icons.shopping_cart_outlined, size: 16),
        label: const Text(label),
      ),
    );
  }
}
