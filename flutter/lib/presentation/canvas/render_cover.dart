import '../../application/garden_controller.dart';
import '../../domain/document.dart';
import '../../domain/layer.dart';

/// Resolve the vault reference while gathering the scene, not while painting.
/// Render is a representative canopy, not a growth/date simulation: an
/// undated or planned crop is shown, but a termination on/before the garden's
/// current day ends it (the same termination boundary as CoverSowing).
/// Missing/deleted varieties never infer a crop from the saved display name.
Map<String, String> renderCoverCropIds(
  GardenDocument document,
  GardenController? garden,
) {
  if (garden == null) return const {};
  final today = garden.today;
  return Map.unmodifiable({
    for (final layer in document.layers.values)
      if (layer.properties case ZoneProperties(
        isCover: true,
        cover: final cover?,
      ))
        if (cover.terminatedOn == null || cover.terminatedOn!.isAfter(today))
          if (garden.record.varieties[cover.varietyId] case final variety?)
            layer.id: variety.cropId,
  });
}

/// The catalog crop each planting layer's seed is, by layer, for choosing
/// its plant picture in Render. Resolved through the Seed Vault variety,
/// never guessed from the saved display name.
Map<String, String> renderPlantCropIds(
  GardenDocument document,
  GardenController? garden,
) {
  if (garden == null) return const {};
  return Map.unmodifiable({
    for (final layer in document.layers.values)
      if (layer.properties case ZoneProperties(seed: final seed?))
        if (garden.record.varieties[seed.varietyId] case final variety?)
          layer.id: variety.cropId,
  });
}
