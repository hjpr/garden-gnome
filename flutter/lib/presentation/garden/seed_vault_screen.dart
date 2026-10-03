import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../application/garden_controller.dart';
import '../../application/toasts.dart';
import '../../domain/grow/crop.dart';
import '../../domain/grow/variety.dart';
import '../../persistence/garden_record_codec.dart';
import '../theme.dart';
import '../widgets/icon_controls.dart';
import '../widgets/panel.dart' show EmptyPanelText;
import 'add_variety_dialog.dart';
import 'garden_card.dart';
import 'variety_detail.dart';

/// The Seed Vault: every variety the gardener has, filterable, and the
/// selected one's record. Values left blank use the crop's catalog
/// value, shown greyed in the empty box.
class SeedVaultBody extends StatefulWidget {
  const SeedVaultBody({super.key, required this.garden});

  final GardenController garden;

  @override
  State<SeedVaultBody> createState() => _SeedVaultBodyState();
}

/// Filters for the vault list.
enum _SeasonFilter { all, cool, warm }

class _SeedVaultBodyState extends State<SeedVaultBody> {
  String _query = '';
  String? _category;
  _SeasonFilter _season = _SeasonFilter.all;
  SowingMethod? _sowing;
  String? _selectedId;

  GardenController get _garden => widget.garden;

  List<VarietyProfile> get _filtered {
    final q = _query.trim().toLowerCase();
    return [
      for (final p in _garden.profiles)
        if ((q.isEmpty ||
                p.variety.name.toLowerCase().contains(q) ||
                p.crop.name.toLowerCase().contains(q) ||
                (p.variety.source ?? '').toLowerCase().contains(q)) &&
            (_category == null || p.crop.category == _category) &&
            (_season == _SeasonFilter.all ||
                p.crop.season.name == _season.name) &&
            (_sowing == null || p.sowing == _sowing))
          p,
    ];
  }

  Future<void> _add() async {
    final result = await showAddVarietyDialog(
      context,
      catalog: _garden.catalog,
    );
    if (result == null) return;
    setState(() => _selectedId = _garden.addVariety(result.$1, result.$2));
  }

  /// Saves every variety as a .seedvault file the gardener keeps.
  Future<void> _export() async {
    const name = 'Seed Vault.seedvault';
    try {
      await XFile.fromData(
        utf8.encode(encodeSeedVault(_garden.record.varieties.values)),
        name: name,
        mimeType: 'application/json',
      ).saveTo(name);
      _garden.toasts.show('Exported $name');
    } catch (_) {
      _garden.toasts.show('Export failed', kind: ToastKind.error);
    }
  }

  /// Adds the varieties from a .seedvault file to this vault. Varieties
  /// already here are skipped, so importing twice adds nothing.
  Future<void> _import() async {
    const group = XTypeGroup(label: 'Seed Vault', extensions: ['seedvault']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    try {
      final varieties = decodeSeedVault(await file.readAsString());
      final (added, skipped) = _garden.importVarieties(varieties);
      _garden.toasts.show(
        'Imported $added ${added == 1 ? 'variety' : 'varieties'}'
        '${skipped > 0 ? ' ($skipped already here or unknown)' : ''}',
      );
    } on GardenRecordFormatError catch (e) {
      _garden.toasts.show('$e', kind: ToastKind.error);
    } catch (_) {
      _garden.toasts.show('That file could not be read', kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final selected = _selectedId == null
        ? null
        : _garden.profileOf(_selectedId!);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 340,
            child: GardenCard(
              title: 'Seed Vault',
              trailing: Text(
                '${list.length} of ${_garden.record.varieties.length}',
                style: const TextStyle(fontSize: 12, color: Palette.muted),
              ),
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                    child: _filters(),
                  ),
                  const Divider(),
                  Expanded(
                    child: list.isEmpty
                        ? EmptyPanelText(
                            _garden.record.varieties.isEmpty
                                ? 'Add a variety to start.'
                                : 'No varieties match.',
                          )
                        : ListView(
                            children: [
                              for (final p in list)
                                _VarietyTile(
                                  profile: p,
                                  selected: p.id == _selectedId,
                                  onTap: () =>
                                      setState(() => _selectedId = p.id),
                                ),
                            ],
                          ),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _garden.catalog.crops.isEmpty
                                ? null
                                : _add,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add variety'),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconAction(
                          iconData: Icons.file_upload_outlined,
                          label: 'Import Seed Vault',
                          onPressed: _garden.catalog.crops.isEmpty
                              ? null
                              : _import,
                        ),
                        IconAction(
                          iconData: Icons.file_download_outlined,
                          label: 'Export Seed Vault',
                          onPressed: _garden.record.varieties.isEmpty
                              ? null
                              : _export,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: selected == null
                ? const GardenCard(
                    title: 'Variety',
                    child: Center(child: EmptyPanelText('Nothing selected.')),
                  )
                : VarietyDetail(
                    key: ValueKey(selected.id),
                    garden: _garden,
                    profile: selected,
                    onRemoved: () => setState(() => _selectedId = null),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    Widget chip(String label, bool on, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 4),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: on,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        selectedColor: Palette.wash,
        side: BorderSide(color: on ? Palette.accent : Palette.panelBorder),
        onSelected: (_) => onTap(),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Search varieties',
            prefixIcon: Icon(Icons.search, size: 18),
            prefixIconConstraints: BoxConstraints(minWidth: 34),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        Wrap(
          children: [
            for (final c in _garden.catalog.categories)
              chip(
                c,
                _category == c,
                () => setState(() => _category = _category == c ? null : c),
              ),
            chip(
              'Cool',
              _season == _SeasonFilter.cool,
              () => setState(
                () => _season = _season == _SeasonFilter.cool
                    ? _SeasonFilter.all
                    : _SeasonFilter.cool,
              ),
            ),
            chip(
              'Warm',
              _season == _SeasonFilter.warm,
              () => setState(
                () => _season = _season == _SeasonFilter.warm
                    ? _SeasonFilter.all
                    : _SeasonFilter.warm,
              ),
            ),
            for (final s in SowingMethod.values.where(
              (s) => s != SowingMethod.either,
            ))
              chip(
                s.label,
                _sowing == s,
                () => setState(() => _sowing = _sowing == s ? null : s),
              ),
          ],
        ),
      ],
    );
  }
}

class _VarietyTile extends StatelessWidget {
  const _VarietyTile({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final VarietyProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = profile.variety;
    return Material(
      color: selected ? Palette.wash : Palette.paper,
      child: InkWell(
        onTap: onTap,
        hoverColor: Palette.hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: selected ? Palette.accent : Palette.ink,
                      ),
                    ),
                    Text(
                      [
                        profile.crop.name,
                        '${profile.daysToMaturity} days',
                        if ((v.seedsOnHand ?? '').isNotEmpty) v.seedsOnHand!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                profile.crop.season == Season.cool
                    ? Icons.ac_unit
                    : Icons.wb_sunny_outlined,
                size: 14,
                color: Palette.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
