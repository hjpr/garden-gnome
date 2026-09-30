import 'dart:convert';

import '../domain/grow/crop.dart';
import 'int_range_codec.dart';
import 'length_range_codec.dart';

/// Reads the bundled crop catalog (assets/catalog/crops.json, made by
/// tools/johnnys-catalog). Crops missing a required value are skipped
/// rather than failing the whole catalog.
CropCatalog decodeCropCatalog(String text, {String? varietiesText}) {
  final json = jsonDecode(text) as Map<String, Object?>;
  final varietiesJson = varietiesText == null
      ? json
      : jsonDecode(varietiesText) as Map<String, Object?>;
  final crops = <Crop>[];
  for (final entry in (json['crops'] as List? ?? const [])) {
    final crop = _crop(entry);
    if (crop != null) crops.add(crop);
  }
  final cropIds = {for (final crop in crops) crop.id};
  final varietyIds = <String>{};
  return CropCatalog(
    crops,
    varieties: [
      for (final entry in (varietiesJson['varieties'] as List? ?? const []))
        if (_variety(entry) case final variety?)
          if (cropIds.contains(variety.cropId) && varietyIds.add(variety.id))
            variety,
    ],
    source: json['source'] as String? ?? '',
    fetched: json['fetched'] as String? ?? '',
  );
}

CatalogVariety? _variety(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'], cropId = raw['cropId'], name = raw['name'];
  if (id is! String || cropId is! String || name is! String) return null;
  if (id.trim().isEmpty || cropId.trim().isEmpty || name.trim().isEmpty) {
    return null;
  }
  final url = raw['url'];
  if (url != null && url is! String) return null;
  return CatalogVariety(
    id: id,
    cropId: cropId,
    name: name,
    url: url as String?,
  );
}

Crop? _crop(Object? raw) {
  if (raw is! Map) return null;
  final season = _enum(Season.values, raw['season']);
  final frost = switch (raw['frostTolerance']) {
    'tender' => FrostTolerance.tender,
    'half-hardy' => FrostTolerance.halfHardy,
    'hardy' => FrostTolerance.hardy,
    _ => null,
  };
  final sowing = _enum(SowingMethod.values, raw['sowing']);
  final dtm = decodeRange(raw['daysToMaturity']);
  final plantOut = decodeRange(raw['plantOutWeeks']);
  final inRow = decodeLengthRange(raw['inRowSpacingIn']);
  final between = decodeLengthRange(raw['betweenRowSpacingIn']);
  final harvest = decodeRange(raw['harvestWindowDays']);
  final id = raw['id'], name = raw['name'];
  if (id is! String || name is! String) return null;
  if (season == null || frost == null || sowing == null) return null;
  if (dtm == null || plantOut == null || inRow == null || between == null) {
    return null;
  }
  return Crop(
    id: id,
    name: name,
    category: raw['category'] as String? ?? 'Vegetables',
    url: raw['url'] as String?,
    scientificName: raw['scientificName'] as String?,
    season: season,
    frostTolerance: frost,
    sowing: sowing,
    germinationDays: decodeRange(raw['germinationDays']),
    weeksToTransplant: decodeRange(raw['weeksToTransplant']),
    daysToMaturity: dtm,
    maturityFrom: _enum(MaturityFrom.values, raw['maturityFrom']),
    plantOutWeeks: plantOut,
    fallCrop: raw['fallCrop'] == true,
    overwinterWeeks: decodeRange(raw['overwinterWeeks']),
    successionDays: (raw['successionDays'] as num?)?.round(),
    inRowSpacingIn: inRow,
    betweenRowSpacingIn: between,
    harvestWindowDays: harvest ?? const IntRange(14, 21),
    sowingDepthIn: (raw['sowingDepthIn'] as num?)?.toDouble(),
    soilTempF: decodeRange(raw['soilTempF']),
    sections: List.unmodifiable([
      for (final s in (raw['sections'] as List? ?? const []))
        if (s is Map && s['title'] is String && s['text'] is String)
          CropSection(s['title'] as String, s['text'] as String),
    ]),
    estimated: Set.unmodifiable({
      for (final e in (raw['estimated'] as List? ?? const []))
        if (e is String) e,
    }),
  );
}

T? _enum<T extends Enum>(List<T> values, Object? name) =>
    values.where((v) => v.name == name).firstOrNull;
