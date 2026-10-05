import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/garden_controller.dart';
import '../../domain/grow/climate.dart';
import '../../domain/grow/day.dart';
import '../theme.dart';
import '../widgets/icon_controls.dart';
import '../widgets/property_controls.dart';
import 'garden_card.dart';

/// Hardiness zone, frost dates and latitude: the inputs to every planting
/// window. Frost dates and latitude show as text with a pencil beside
/// them; editing opens dropdowns (and a number box for latitude) in place.
/// A frost date the gardener has not set shows the zone's, greyed.
class ClimateBar extends StatelessWidget {
  const ClimateBar({super.key, required this.garden});

  final GardenController garden;

  @override
  Widget build(BuildContext context) {
    final climate = garden.climate;
    return GardenCard(
      fill: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 28,
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
          FrostDateEditor(
            label: 'Last frost',
            own: climate.lastSpringFrost,
            zoneDefault: climate.zone.lastSpringFrost,
            onChanged: (d) => garden.setFrostDates(lastSpring: () => d),
          ),
          FrostDateEditor(
            label: 'First frost',
            own: climate.firstFallFrost,
            zoneDefault: climate.zone.firstFallFrost,
            onChanged: (d) => garden.setFrostDates(firstFall: () => d),
          ),
          // Day length times the winter windows, so they need it.
          LatitudeEditor(
            latitude: climate.latitude,
            onChanged: garden.setLatitude,
          ),
        ],
      ),
    );
  }
}

/// A label, then either the value with a pencil (and a reset when the
/// gardener has set one), or [editor] with apply and cancel buttons.
class _Editable extends StatelessWidget {
  const _Editable({
    required this.label,
    required this.value,
    required this.valueIsDefault,
    required this.editing,
    required this.onEdit,
    required this.editor,
    required this.onApply,
    required this.onCancel,
    required this.onReset,
    required this.resetLabel,
  });

  final String label;
  final String value;

  /// Greys the value: nothing set, so a default (or nothing) shows.
  final bool valueIsDefault;
  final bool editing;
  final VoidCallback onEdit;
  final Widget editor;
  final VoidCallback? onApply;
  final VoidCallback onCancel;

  /// Clears the gardener's value; null hides the button.
  final VoidCallback? onReset;
  final String resetLabel;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
      const SizedBox(width: 10),
      if (editing) ...[
        editor,
        const SizedBox(width: 4),
        IconAction(
          iconData: Icons.check,
          label: 'Apply $label',
          size: 26,
          onPressed: onApply,
        ),
        IconAction(
          iconData: Icons.close,
          label: 'Cancel $label',
          size: 26,
          onPressed: onCancel,
        ),
      ] else ...[
        Text(
          value,
          key: ValueKey('value-$label'),
          style: TextStyle(
            fontSize: 13,
            color: valueIsDefault ? Palette.faint : Palette.ink,
          ),
        ),
        const SizedBox(width: 2),
        IconAction(
          iconData: Icons.edit_outlined,
          label: 'Edit $label',
          size: 26,
          onPressed: onEdit,
        ),
        if (onReset case final reset?)
          IconAction(
            iconData: Icons.restart_alt,
            label: resetLabel,
            size: 26,
            onPressed: reset,
          ),
      ],
    ],
  );
}

/// A frost date: shown as "Apr 23" (greyed while it is the zone's),
/// edited with a month and a day dropdown. Reset goes back to the zone's.
class FrostDateEditor extends StatefulWidget {
  const FrostDateEditor({
    super.key,
    required this.label,
    required this.own,
    required this.zoneDefault,
    required this.onChanged,
  });

  final String label;

  /// The gardener's date; null uses [zoneDefault].
  final MonthDay? own;
  final MonthDay zoneDefault;
  final ValueChanged<MonthDay?> onChanged;

  @override
  State<FrostDateEditor> createState() => _FrostDateEditorState();
}

class _FrostDateEditorState extends State<FrostDateEditor> {
  /// The month and day being picked; null when not editing.
  (int, int)? _draft;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// Days in [month] of a non-leap year: frost dates recur every year.
  static int _daysIn(int month) => DateTime.utc(2001, month + 1, 0).day;

  void _edit() {
    final d = widget.own ?? widget.zoneDefault;
    setState(() => _draft = (d.month, d.day));
  }

  void _apply() {
    final (month, day) = _draft!;
    final picked = MonthDay(month, day);
    setState(() => _draft = null);
    if (picked != widget.own) widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return _Editable(
      label: widget.label,
      value: (widget.own ?? widget.zoneDefault).toString(),
      valueIsDefault: widget.own == null,
      editing: draft != null,
      onEdit: _edit,
      onApply: _apply,
      onCancel: () => setState(() => _draft = null),
      onReset: widget.own == null ? null : () => widget.onChanged(null),
      resetLabel: "Use the zone's ${widget.label.toLowerCase()}",
      editor: draft == null
          ? const SizedBox.shrink()
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 124,
                  child: CompactDropdown<int>(
                    label: '${widget.label} month',
                    value: draft.$1,
                    items: {for (var m = 1; m <= 12; m++) m: _months[m - 1]},
                    // A day past the new month's end moves to its last.
                    onChanged: (m) => setState(
                      () => _draft = (m, draft.$2.clamp(1, _daysIn(m))),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 70,
                  child: CompactDropdown<int>(
                    // Re-keyed by month, so its list of days follows it.
                    key: ValueKey(('day', draft.$1)),
                    label: '${widget.label} day',
                    value: draft.$2,
                    items: {
                      for (var d = 1; d <= _daysIn(draft.$1); d++) d: '$d',
                    },
                    onChanged: (d) => setState(() => _draft = (draft.$1, d)),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The farm's latitude: shown as "42.3°N", edited by typing the degrees
/// and picking N or S. Reset clears it.
class LatitudeEditor extends StatefulWidget {
  const LatitudeEditor({
    super.key,
    required this.latitude,
    required this.onChanged,
  });

  /// Degrees, negative south of the equator; null when not set.
  final double? latitude;
  final ValueChanged<double?> onChanged;

  @override
  State<LatitudeEditor> createState() => _LatitudeEditorState();
}

class _LatitudeEditorState extends State<LatitudeEditor> {
  bool _editing = false;
  bool _north = true;
  final _degrees = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _degrees.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Degrees typed, or null when not a number from 0 to 90.
  double? get _typed {
    final v = double.tryParse(_degrees.text.trim());
    return v == null || v < 0 || v > 90 ? null : v;
  }

  void _edit() {
    final lat = widget.latitude;
    _degrees.text = lat == null ? '' : formatLatitudeDegrees(lat.abs());
    setState(() {
      _north = lat == null || lat >= 0;
      _editing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _apply() {
    final degrees = _typed;
    if (degrees == null) return;
    final value = _north ? degrees : -degrees;
    setState(() => _editing = false);
    if (value != widget.latitude) widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final lat = widget.latitude;
    return _Editable(
      label: 'Latitude',
      value: lat == null ? 'Not set' : formatLatitude(lat),
      valueIsDefault: lat == null,
      editing: _editing,
      onEdit: _edit,
      onApply: _typed == null ? null : _apply,
      onCancel: () => setState(() => _editing = false),
      onReset: lat == null ? null : () => widget.onChanged(null),
      resetLabel: 'Clear latitude',
      editor: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 76,
            child: TextField(
              key: const ValueKey('latitude-degrees'),
              controller: _degrees,
              focusNode: _focus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: '42.3',
                suffixText: '°',
                errorText: _degrees.text.isNotEmpty && _typed == null
                    ? '0–90'
                    : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _apply(),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: CompactDropdown<bool>(
              label: 'North or south',
              value: _north,
              items: const {true: 'N', false: 'S'},
              onChanged: (north) => setState(() => _north = north),
            ),
          ),
        ],
      ),
    );
  }
}

/// Up to two decimals, trailing zeros dropped.
String formatLatitudeDegrees(double degrees) =>
    degrees.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// "42.3°N" or "33.9°S".
String formatLatitude(double latitude) =>
    '${formatLatitudeDegrees(latitude.abs())}°${latitude < 0 ? 'S' : 'N'}';
