import 'dart:math' as math;

import '../domain/grow/variety.dart';
import '../domain/layer.dart';
import '../domain/planar.dart';
import '../domain/vec.dart';
import 'editor_controller.dart';

/// Metres in one inch; the crop catalog gives spacings in inches.
const metresPerInch = 0.0254;

/// Use the smallest in-row recommendation as diameter. Convert the
/// between-row centre distance into an empty gap, never a negative one.
ZoneSeed seedFromProfile(VarietyProfile profile) {
  final size = _positive(profile.inRowSpacingIn.min) * metresPerInch;
  return ZoneSeed(
    varietyId: profile.id,
    name: profile.displayName,
    size: size,
    spacing: math.max(
      0,
      profile.betweenRowSpacingIn.min * metresPerInch - size,
    ),
  );
}

/// A spacing of at least half an inch: some catalog entries give 0 for
/// broadcast crops, which would ask for endless plants.
double _positive(num inches) => inches < 0.5 ? 0.5 : inches.toDouble();

/// The grow zone a seed dropped at [world] lands on: the topmost one
/// (drawn last) whose land contains the point and that can be changed.
/// Null when the point is not inside one.
String? growZoneAt(EditorController editor, Vec world) {
  final document = editor.document;
  for (final id in document.drawingOrder.reversed) {
    if (!editor.isGrowZone(id) || editor.isUnreachable(id)) continue;
    final region = document.geometryOf(id).region;
    if (region != null && region.locate(world) == PointLocation.inside) {
      return id;
    }
  }
  return null;
}

/// Plants [profile] in the grow zone under [world], as one Undo step, and
/// selects that zone. Returns false, with the reason in the status bar,
/// when there is no grow zone there.
bool dropSeed(EditorController editor, VarietyProfile profile, Vec world) {
  final layerId = growZoneAt(editor, world);
  if (layerId == null) {
    editor.showNotice('Drop seeds inside a planting');
    return false;
  }
  return plantIn(editor, layerId, profile);
}

/// Plants [profile] in grow zone [layerId]. Spacings already typed for
/// the same variety are kept, so dropping it again changes nothing.
bool plantIn(EditorController editor, String layerId, VarietyProfile profile) {
  if (!editor.isGrowZone(layerId)) {
    editor.showNotice('Seeds are planted in plantings');
    return false;
  }
  editor.selectLayer(layerId);
  editor.showNotice(null);
  editor.setSeed(layerId, _seedFor(editor, layerId, profile));
  return true;
}

/// The seed [profile] gets in [layerId], keeping spacings already typed
/// there for the same variety.
ZoneSeed _seedFor(
  EditorController editor,
  String layerId,
  VarietyProfile profile,
) {
  final current = switch (editor.document.layers[layerId]?.properties) {
    ZoneProperties p => p.seed,
    _ => null,
  };
  return current?.varietyId == profile.id ? current! : seedFromProfile(profile);
}

/// A greenhouse sowing dragged from Plant mode's Greenhouse panel.
class TrayDrag {
  const TrayDrag({
    required this.plantingId,
    required this.profile,
    required this.outOn,
  });

  final String plantingId;
  final VarietyProfile profile;

  /// When it should go out: when it is expected to be ready, or today if
  /// that has passed.
  final DateTime outOn;
}

/// Plans the greenhouse sowing in [tray] into the planting under [world]
/// as one Undo step, and selects that planting. Returns false, with the
/// reason in the status bar, when there is no planting there.
bool dropTray(EditorController editor, TrayDrag tray, Vec world) {
  final layerId = growZoneAt(editor, world);
  if (layerId == null) {
    editor.showNotice('Drop greenhouse plants inside a planting');
    return false;
  }
  editor.selectLayer(layerId);
  editor.showNotice(null);
  editor.placeTray(
    layerId,
    tray.plantingId,
    _seedFor(editor, layerId, tray.profile),
    tray.outOn,
  );
  return true;
}
