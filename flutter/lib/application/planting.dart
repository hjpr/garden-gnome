import '../domain/grow/variety.dart';
import '../domain/layer.dart';
import '../domain/planar.dart';
import '../domain/vec.dart';
import '../domain/zone_ground.dart';
import 'editor_controller.dart';

/// Metres in one inch; the crop catalog gives spacings in inches.
const metresPerInch = 0.0254;

/// The closest recommended spacings, centre to centre as the catalog
/// gives them.
ZoneSeed seedFromProfile(VarietyProfile profile) => ZoneSeed(
  varietyId: profile.id,
  name: profile.displayName,
  inRow: _positive(profile.inRowSpacingIn.min) * metresPerInch,
  betweenRows: _positive(profile.betweenRowSpacingIn.min) * metresPerInch,
);

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

/// The Cover bed a cover crop dropped at [world] lands on: the topmost
/// reachable one whose land contains the point, or null.
String? coverBedAt(EditorController editor, Vec world) {
  final document = editor.document;
  for (final id in document.drawingOrder.reversed) {
    if (!editor.isCoverBed(id) || editor.isUnreachable(id)) continue;
    final region = document.geometryOf(id).region;
    if (region != null && region.locate(world) == PointLocation.inside) {
      return id;
    }
  }
  return null;
}

/// Why a planting cannot take seed: it lies over a Cover bed.
const overCoverNotice =
    'Plantings over cover crops cannot be seeded. Make the bed Flat or Row '
    'first';

/// What a drag dropped at [world] would land on, or null when it would be
/// refused: a cover crop's Cover bed, or a seed's or tray's planting
/// (not one over a Cover bed). Used for the drop highlight.
String? dropTargetAt(EditorController editor, Object? data, Vec world) =>
    switch (data) {
      CoverDrag() => coverBedAt(editor, world),
      VarietyProfile() || TrayDrag() => switch (growZoneAt(editor, world)) {
        final id? when !editor.document.isOverCover(id) => id,
        _ => null,
      },
      _ => null,
    };

/// Plants [profile] in the grow zone under [world], as one Undo step, and
/// selects that zone. Returns false, with the reason in the status bar,
/// when there is no grow zone there.
bool dropSeed(EditorController editor, VarietyProfile profile, Vec world) {
  final layerId = growZoneAt(editor, world);
  if (layerId == null) {
    editor.showNotice(
      coverBedAt(editor, world) == null
          ? 'Drop seeds inside a planting'
          : 'Only cover crops are sown on Cover beds',
    );
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
  if (editor.document.isOverCover(layerId)) {
    editor.showNotice(overCoverNotice);
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

/// A cover crop variety dragged from Plant mode's Seeds panel.
class CoverDrag {
  const CoverDrag({required this.varietyId, required this.name});

  final String varietyId;

  /// e.g. "Crimson Clover · Crimson Clover", kept with the bed.
  final String name;
}

/// Sows [cover] on the Cover bed under [world] as one Undo step and
/// selects it. Returns false, with the reason in the status bar, when
/// there is no Cover bed there.
bool dropCover(EditorController editor, CoverDrag cover, Vec world) {
  final layerId = coverBedAt(editor, world);
  if (layerId == null) {
    editor.showNotice('Drop cover crops inside a Cover bed');
    return false;
  }
  return sowCover(editor, layerId, cover);
}

/// Sows [cover] across Cover bed [layerId], keeping any dates already
/// set there.
bool sowCover(EditorController editor, String layerId, CoverDrag cover) {
  final properties = editor.document.layers[layerId]?.properties;
  if (properties is! ZoneProperties || !properties.isCover) {
    editor.showNotice('Cover crops are sown on Cover beds');
    return false;
  }
  editor.selectLayer(layerId);
  editor.showNotice(null);
  final current = properties.cover;
  editor.setCover(
    layerId,
    CoverSowing(
      varietyId: cover.varietyId,
      name: cover.name,
      sownOn: current?.sownOn,
      terminatedOn: current?.terminatedOn,
    ),
  );
  return true;
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
  if (editor.document.isOverCover(layerId)) {
    editor.showNotice(overCoverNotice);
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
