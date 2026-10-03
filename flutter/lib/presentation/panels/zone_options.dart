import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../domain/layer.dart';
import '../../domain/plant_layout.dart';
import '../../domain/units.dart';
import '../../domain/zone_ground.dart';
import '../theme.dart';
import '../widgets/draft_text_field.dart';
import '../widgets/icon_controls.dart';
import '../widgets/property_controls.dart';
import 'layer_fields.dart';
import 'measure_field.dart';
import 'day_field.dart';

class ZoneOptions extends StatelessWidget {
  const ZoneOptions({
    super.key,
    required this.editor,
    required this.layer,
    required this.properties,
    required this.editable,
  });

  final EditorController editor;
  final Layer layer;
  final ZoneProperties properties;
  final bool editable;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: _zoneOptions(layer, properties, editable),
  );

  List<Widget> _zoneOptions(Layer layer, ZoneProperties p, bool editable) => [
    if (p.isGrow)
      _plantingGroup(layer, p, editable)
    else ...[
      PropertyGroup(
        title: 'OPTIONS',
        children: [
          LayerColorField(
            editor: editor,
            layer: layer,
            value: p.color,
            choices: OutlineColor.zoneChoices,
            change: (c) => p.copyWith(color: c),
            enabled: editable,
          ),
        ],
      ),
      // Ground is set with the Ground tool; only Row and Flat have
      // settings here.
      if (p.ground == GroundType.row) _rowGroup(layer, p, editable),
      if (p.ground == GroundType.flat)
        PropertyGroup(
          title: 'GROUND',
          children: [_directionField(layer, p, editable)],
        ),
    ],
  ];

  Widget _plantingGroup(Layer layer, ZoneProperties p, bool editable) {
    final units = editor.settings.units;
    final seed = p.seed;
    final seedEditable = editable && seed != null;
    final layout = editor.document.plantLayoutOf(layer.id);
    final sowing = editor.document.currentPlantingOf(layer.id);
    void setSeed(ZoneSeed Function(ZoneSeed) change) {
      final current = editor.document.layers[layer.id]?.properties;
      if (current is ZoneProperties && current.seed != null) {
        editor.setSeed(layer.id, change(current.seed!));
      }
    }

    return PropertyGroup(
      title: 'GROW',
      children: [
        PropertyRow(
          label: 'Seed',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  seed?.name ?? '—',
                  key: const ValueKey('planted-seed'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: seed == null ? Palette.faint : Palette.ink,
                  ),
                ),
              ),
              IconAction(
                iconData: Icons.delete_outline,
                label: 'Remove seed',
                size: 24,
                onPressed: seedEditable
                    ? () => editor.setSeed(layer.id, null)
                    : null,
              ),
            ],
          ),
        ),
        _readout(
          'Plants',
          layout == null ? '—' : '${layout.count}',
          seed != null,
        ),
        MeasureField(
          editor: editor,
          ownerId: layer.id,
          field: 'seed-size',
          label: 'Size',
          unit: units.symbol,
          metres: seed?.size ?? 0,
          toDisplay: units.fromMetres,
          fromDisplay: units.toMetres,
          enabled: seedEditable,
          minimum: Minimum.aboveZero,
          apply: (v) => setSeed((s) => s.copyWith(size: v)),
        ),
        MeasureField(
          editor: editor,
          ownerId: layer.id,
          field: 'seed-spacing',
          label: 'Spacing',
          unit: units.symbol,
          metres: seed?.spacing ?? 0,
          toDisplay: units.fromMetres,
          fromDisplay: units.toMetres,
          enabled: seedEditable,
          minimum: Minimum.zero,
          apply: (v) => setSeed((s) => s.copyWith(spacing: v)),
        ),
        // Only row beds take lines; flat ground is a grid.
        _linesField(
          layer,
          seed,
          seedEditable && (layout?.soils.contains(GroundType.row) ?? false),
          (lines) => setSeed((s) => s.copyWith(lines: () => lines)),
        ),
        PropertyRow(
          label: 'Sown',
          child: DayField(
            label: 'Sown',
            day: sowing?.sownOn,
            enabled: seedEditable,
            onChanged: (day) => editor.setSownOn(layer.id, day),
          ),
        ),
        PropertyRow(
          label: 'Transplanted',
          child: DayField(
            label: 'Transplanted',
            day: sowing?.plantedOutOn,
            first: sowing?.sownOn,
            enabled: seedEditable && sowing != null,
            onChanged: (day) => editor.setTransplantedOn(layer.id, day),
            onCleared: () => editor.setTransplantedOn(layer.id, null),
          ),
        ),
      ],
    );
  }

  Widget _rowGroup(Layer layer, ZoneProperties p, bool editable) {
    final document = editor.document;
    final units = editor.settings.units;
    final rowUnit = units == Units.feet ? 'in' : units.symbol;
    final metresPerRowUnit = units == Units.feet ? 0.0254 : units.metresPerUnit;
    double rowToDisplay(double metres) => metres / metresPerRowUnit;
    double rowFromDisplay(double value) => value * metresPerRowUnit;
    final layout = document.rowLayoutOf(layer.id);
    void setRows(RowSpec Function(RowSpec) change) {
      final current = editor.document.layers[layer.id]?.properties;
      if (current is ZoneProperties) {
        editor.setRows(layer.id, change(current.rows));
      }
    }

    return PropertyGroup(
      title: 'GROUND',
      children: [
        MeasureField(
          editor: editor,
          ownerId: layer.id,
          field: 'row-width',
          label: 'Row width',
          unit: rowUnit,
          metres: p.rows.width,
          toDisplay: rowToDisplay,
          fromDisplay: rowFromDisplay,
          enabled: editable,
          minimum: Minimum.aboveZero,
          apply: (w) => setRows((r) => r.copyWith(width: w)),
        ),
        MeasureField(
          editor: editor,
          ownerId: layer.id,
          field: 'row-spacing',
          label: 'Spacing',
          unit: rowUnit,
          metres: p.rows.spacing,
          toDisplay: rowToDisplay,
          fromDisplay: rowFromDisplay,
          enabled: editable,
          minimum: Minimum.zero,
          apply: (s) => setRows((r) => r.copyWith(spacing: s)),
        ),
        MeasureField(
          editor: editor,
          ownerId: layer.id,
          field: 'row-border',
          label: 'Border',
          unit: rowUnit,
          metres: p.rows.border,
          toDisplay: rowToDisplay,
          fromDisplay: rowFromDisplay,
          enabled: editable,
          minimum: Minimum.zero,
          apply: (b) => setRows((r) => r.copyWith(border: b)),
        ),
        _directionField(layer, p, editable),
        _readout('Rows', layout == null ? '—' : '${layout.rowCount}', true),
        _readout(
          'Row length',
          layout == null ? '—' : units.format(layout.totalLength),
          true,
        ),
      ],
    );
  }

  Widget _directionField(Layer layer, ZoneProperties p, bool editable) =>
      MeasureField(
        editor: editor,
        ownerId: layer.id,
        field: 'row-direction',
        label: 'Direction',
        unit: '°',
        metres: p.rows.direction,
        enabled: editable,
        minimum: Minimum.none,
        // 180° wraps back to 0°, since rows run both ways.
        step: 1,
        bigStep: 15,
        apply: (direction) {
          final current = editor.document.layers[layer.id]?.properties;
          if (current is ZoneProperties) {
            editor.setRows(
              layer.id,
              current.rows.copyWith(direction: direction),
            );
          }
        },
      );

  /// Lines of plants per row bed: a whole number, or All to fill the row.
  /// Blank or "all" means All. The arrows step 1 line; below 1 is All,
  /// and Up from All starts at 1.
  Widget _linesField(
    Layer layer,
    ZoneSeed? seed,
    bool enabled,
    ValueChanged<int?> apply,
  ) {
    int? parse(String text) {
      final t = text.trim().toLowerCase();
      return t.isEmpty || t == linesAll.toLowerCase() ? null : int.parse(t);
    }

    void commit(int? lines) {
      if (lines != seed?.lines) apply(lines);
    }

    // The most lines the spacing lets the row beds hold: more needs a
    // smaller Size or Spacing.
    final most = seed == null
        ? null
        : editor.document.maxLinesOf(layer.id, seed);
    final tooMany = most == null
        ? null
        : 'At most $most ${most == 1 ? 'line fits' : 'lines fit'}. '
              'Reduce Spacing for more';

    return PropertyRow(
      label: 'Lines',
      child: DraftTextField(
        key: ValueKey(('lines', layer.id)),
        editor: editor,
        draftKey: '${layer.id}/seed-lines',
        layerId: layer.id,
        committedText: seed?.lines?.toString() ?? linesAll,
        label: 'Lines',
        enabled: enabled,
        check: (text) {
          final t = text.trim().toLowerCase();
          if (t.isEmpty || t == linesAll.toLowerCase()) return null;
          final n = int.tryParse(t);
          if (n == null || n < 1) return 'Enter 1 or more, or All';
          if (most != null && n > most) return tooMany;
          return null;
        },
        apply: (text) => commit(parse(text)),
        onStep: (text, direction, {required bool big}) {
          final current = int.tryParse(text.trim()) ?? seed?.lines;
          if (current == null) {
            if (direction > 0) commit(1);
            return;
          }
          var next = current + direction * (big ? 5 : 1);
          if (most != null && next > most) {
            if (current >= most) return editor.showNotice(tooMany);
            next = most;
          }
          commit(next < 1 ? null : next);
        },
      ),
    );
  }

  /// What the Lines box shows when the row is filled.
  static const linesAll = 'All';

  /// A worked-out value, greyed out when it does not apply.
  Widget _readout(String label, String value, bool active) => PropertyRow(
    label: label,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        value,
        key: ValueKey('readout-$label'),
        style: TextStyle(
          fontSize: 13,
          color: active ? Palette.ink : Palette.faint,
        ),
      ),
    ),
  );
}
