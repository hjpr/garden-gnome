import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../application/camera.dart';
import '../application/workspace_settings.dart';
import '../domain/document.dart';
import '../domain/geometry.dart';
import '../domain/layer.dart';
import '../domain/units.dart';
import '../domain/vec.dart';

/// Workspace choices and the view, remembered per drawing on this device.
///
/// Stored apart from the drawing, so they never mark it as changed. Also
/// keeps the highest ID numbers used, so Undo never lets one be reused.
class WorkspaceStore {
  static const _prefix = 'garden_gnome.workspace.';

  Future<(WorkspaceSettings, Camera)?> load(String documentId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$documentId');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final a = json['appearance'] as Map<String, Object?>;
      // Older saves chose between grid and drawing snapping; drawing
      // snapping became Guides.
      final snapping = json['snapping'] as bool;
      final oldDrawingSnap = json['snap_mode'] == 'drawing';
      final settings = WorkspaceSettings(
        units: Units.values.byName(json['units'] as String),
        // Saves from before area units matched them to the length units.
        areaUnits:
            AreaUnits.values
                .where((u) => u.name == json['area_units'])
                .firstOrNull ??
            (json['units'] == Units.metres.name
                ? AreaUnits.squareMetres
                : AreaUnits.squareFeet),
        snappingEnabled: snapping && !oldDrawingSnap,
        guidesEnabled: json['guides'] as bool? ?? (snapping && oldDrawingSnap),
        menuScale: MenuScale.values.byName(json['menu_scale'] as String),
        hiddenPanels: _panels(json['hidden']),
        minimizedPanels: _panels(json['minimized']),
        docks: DockLayout.restore(
          left: _names(json['left_order']),
          right: _names(json['right_order']),
          folded: _names(json['folded_docks']),
          widths: {
            for (final e in ((json['dock_widths'] as Map?) ?? const {}).entries)
              e.key as String: (e.value as num).toDouble(),
          },
        ),
        appearance: Appearance(
          lineWidth: (a['line_width'] as num).toDouble(),
          gridThickness: (a['grid_thickness'] as num).toDouble(),
          gridColor: a['grid_color'] as int,
          gridOpacity: (a['grid_opacity'] as num).toDouble(),
          zoomLimits: ZoomLimits(
            min: (a['zoom_min'] as num).toDouble(),
            max: (a['zoom_max'] as num).toDouble(),
          ),
          historyCapacity: a['history_capacity'] as int,
          toastPosition:
              ToastPosition.values
                  .where((p) => p.name == a['toast_position'])
                  .firstOrNull ??
              ToastPosition.bottom,
        ),
      );
      final c = json['camera'] as Map<String, Object?>;
      final camera = Camera(
        topLeft: Vec((c['x'] as num).toDouble(), (c['y'] as num).toDouble()),
        zoom: settings.appearance.zoomLimits.clamp(
          (c['zoom'] as num).toDouble(),
        ),
      );
      return (settings, camera);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    String documentId,
    WorkspaceSettings settings,
    Camera camera,
    CounterLedger ledger,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final a = settings.appearance;
    await prefs.setString(
      '$_prefix$documentId',
      jsonEncode({
        'units': settings.units.name,
        'area_units': settings.areaUnits.name,
        'snapping': settings.snappingEnabled,
        'guides': settings.guidesEnabled,
        'menu_scale': settings.menuScale.name,
        'hidden': [for (final p in settings.hiddenPanels) p.name],
        'minimized': [for (final p in settings.minimizedPanels) p.name],
        'left_order': [for (final p in settings.docks.left) p.name],
        'right_order': [for (final p in settings.docks.right) p.name],
        'folded_docks': [for (final d in settings.docks.folded) d.name],
        'dock_widths': {
          for (final e in settings.docks.widths.entries) e.key.name: e.value,
        },
        'appearance': {
          'line_width': a.lineWidth,
          'grid_thickness': a.gridThickness,
          'grid_color': a.gridColor,
          'grid_opacity': a.gridOpacity,
          'zoom_min': a.zoomLimits.min,
          'zoom_max': a.zoomLimits.max,
          'history_capacity': a.historyCapacity,
          'toast_position': a.toastPosition.name,
        },
        'camera': {
          'x': camera.topLeft.x,
          'y': camera.topLeft.y,
          'zoom': camera.zoom,
        },
        'counters': {
          'names': {for (final e in ledger.names.entries) e.key.name: e.value},
          'geometry': {
            for (final e in ledger.geometry.entries)
              e.key: [
                e.value.points,
                e.value.lines,
                e.value.circles,
                e.value.shapes,
              ],
          },
        },
      }),
    );
  }

  /// The highest ID numbers this device has seen for [documentId].
  Future<CounterLedger> counters(String documentId) async {
    final ledger = CounterLedger();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$documentId');
    if (raw == null) return ledger;
    try {
      final json = (jsonDecode(raw) as Map)['counters'] as Map;
      (json['names'] as Map).forEach((k, v) {
        ledger.names[LayerKind.values.byName(k as String)] = v as int;
      });
      (json['geometry'] as Map).forEach((k, v) {
        final n = (v as List).cast<int>();
        ledger.geometry[k as String] = IdCounters(
          points: n[0],
          lines: n[1],
          circles: n[2],
          shapes: n[3],
        );
      });
    } catch (_) {
      // Unreadable local records are ignored; saved counters still apply.
    }
    return ledger;
  }

  /// Panels named in [value]; names this version does not know are skipped.
  static Set<PanelId> _panels(Object? value) => {
    for (final name in _names(value))
      for (final id in PanelId.values)
        if (id.name == name) id,
  };

  static List<String> _names(Object? value) => [
    for (final name in (value as List? ?? const [])) name as String,
  ];
}
