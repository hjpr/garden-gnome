import 'dart:convert';

import '../application/storage_error.dart';
import '../domain/grow/climate.dart';
import '../domain/grow/crop.dart';
import '../domain/grow/day.dart';
import '../domain/grow/garden_record.dart';
import '../domain/grow/planting.dart';
import '../domain/grow/variety.dart';
import 'int_range_codec.dart';
import 'length_range_codec.dart';

export '../application/storage_error.dart' show GardenRecordFormatError;

/// Version of the garden record format. Bump when an older reader would
/// silently drop new data.
const int gardenRecordVersion = 1;

String encodeGardenRecord(GardenRecord record) => jsonEncode({
  'version': gardenRecordVersion,
  'counter': record.counter,
  'climate': climateToJson(record.climate),
  'varieties': [for (final v in record.varieties.values) _variety(v)],
  'plantings': [for (final p in record.plantings.values) plantingToJson(p)],
});

/// Reads a stored record. This is the gardener's own data, so anything
/// that cannot be read as written is refused rather than guessed at:
/// the caller keeps the stored text and the gardener loses nothing.
GardenRecord decodeGardenRecord(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw const GardenRecordFormatError('The garden record is damaged');
  }
  if (decoded is! Map) {
    throw const GardenRecordFormatError('The garden record is damaged');
  }
  final json = decoded.cast<String, Object?>();
  final version = json['version'];
  if (version is! int || version < 1) {
    throw const GardenRecordFormatError('The garden record is damaged');
  }
  if (version > gardenRecordVersion) {
    throw const GardenRecordFormatError(
      'The garden record was saved by a newer Garden Gnome',
    );
  }
  try {
    return _record(json);
  } on FormatException catch (e) {
    throw GardenRecordFormatError('The garden record is damaged: ${e.message}');
  }
}

const String seedVaultFormat = 'garden-gnome-seed-vault';
const int seedVaultVersion = 1;

/// The Seed Vault on its own, for keeping a copy or moving it to another
/// browser. Plantings and climate belong to a farm, so they are left out.
String encodeSeedVault(Iterable<Variety> varieties) =>
    const JsonEncoder.withIndent('  ').convert({
      'format': seedVaultFormat,
      'version': seedVaultVersion,
      'varieties': [for (final v in varieties) _variety(v)],
    });

/// Reads an exported Seed Vault. Anything not written by [encodeSeedVault]
/// is refused whole, so a bad file adds nothing.
List<Variety> decodeSeedVault(String text) {
  const damaged = GardenRecordFormatError('That is not a Seed Vault file');
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw damaged;
  }
  if (decoded is! Map || decoded['format'] != seedVaultFormat) throw damaged;
  final version = decoded['version'];
  if (version is! int || version < 1) throw damaged;
  if (version > seedVaultVersion) {
    throw const GardenRecordFormatError(
      'That Seed Vault was saved by a newer Garden Gnome',
    );
  }
  try {
    return [
      for (final raw in _list(decoded['varieties'], 'varieties'))
        _readVariety(raw),
    ];
  } on FormatException catch (e) {
    throw GardenRecordFormatError(
      'The Seed Vault file is damaged: ${e.message}',
    );
  }
}

GardenRecord _record(Map<String, Object?> json) {
  final climate = _map(json['climate'] ?? const <String, Object?>{}, 'climate');
  final varieties = _unique(
    [
      for (final raw in _list(json['varieties'], 'varieties'))
        _readVariety(raw),
    ],
    (v) => v.id,
    'variety',
  );
  final plantings = _unique(
    [
      for (final raw in _list(json['plantings'], 'plantings'))
        plantingFromJson(raw),
    ],
    (p) => p.id,
    'planting',
  );
  for (final p in plantings.values) {
    if (!varieties.containsKey(p.varietyId)) {
      throw FormatException('planting ${p.id} names a missing variety');
    }
  }
  // A counter behind the IDs it issued would hand one out twice, so it is
  // brought up to them. Nothing is lost by raising it.
  final issued = [...varieties.keys, ...plantings.keys].map(_idNumber);
  final counter = issued.fold(
    _count(json['counter'], 'counter'),
    (highest, n) => n > highest ? n : highest,
  );
  return GardenRecord(
    counter: counter,
    climate: climateFromJson(climate),
    varieties: varieties,
    plantings: plantings,
  );
}

Map<String, Object?> _variety(Variety v) => {
  'id': v.id,
  'crop': v.cropId,
  'name': v.name,
  'source': v.source,
  'product_code': v.productCode,
  'url': v.url,
  'seeds_on_hand': v.seedsOnHand,
  'year_packed': v.yearPacked,
  'organic': v.organic,
  'notes': v.notes,
  'days_to_maturity': encodeRange(v.daysToMaturity),
  'germination_days': encodeRange(v.germinationDays),
  'weeks_to_transplant': encodeRange(v.weeksToTransplant),
  'sowing': v.sowing?.name,
  'in_row_spacing_in': encodeLengthRange(v.inRowSpacingIn),
  'between_row_spacing_in': encodeLengthRange(v.betweenRowSpacingIn),
  'harvest_window_days': encodeRange(v.harvestWindowDays),
};

Variety _readVariety(Object? raw) {
  final j = _map(raw, 'variety');
  return Variety(
    id: _string(j['id'], 'variety ID'),
    cropId: _string(j['crop'], 'variety crop'),
    name: _string(j['name'], 'variety name'),
    source: _optionalString(j['source'], 'variety source'),
    productCode: _optionalString(j['product_code'], 'product code'),
    url: _optionalString(j['url'], 'variety URL'),
    seedsOnHand: _optionalString(j['seeds_on_hand'], 'seeds on hand'),
    yearPacked: _optionalInt(j['year_packed'], 'year packed'),
    organic: _bool(j['organic'], 'organic') ?? false,
    notes: _optionalString(j['notes'], 'variety notes') ?? '',
    daysToMaturity: strictRange(j['days_to_maturity']),
    germinationDays: strictRange(j['germination_days']),
    weeksToTransplant: strictRange(j['weeks_to_transplant']),
    sowing: _optionalEnum(SowingMethod.values, j['sowing'], 'sowing'),
    inRowSpacingIn: strictLengthRange(j['in_row_spacing_in']),
    betweenRowSpacingIn: strictLengthRange(j['between_row_spacing_in']),
    harvestWindowDays: strictRange(j['harvest_window_days']),
  );
}

Map<String, Object?> climateToJson(Climate c) => {
  'zone': c.zone.code,
  'last_spring_frost': c.lastSpringFrost?.code,
  'first_fall_frost': c.firstFallFrost?.code,
};

/// Throws [FormatException] when a value cannot be read.
Climate climateFromJson(Map<String, Object?> json) => Climate(
  zone: _zone(json['zone']),
  lastSpringFrost: _monthDay(json['last_spring_frost']),
  firstFallFrost: _monthDay(json['first_fall_frost']),
);

Map<String, Object?> plantingToJson(Planting p) => {
  'id': p.id,
  'variety': p.varietyId,
  'sown': _date(p.sownOn),
  'indoors': p.startedIndoors,
  'planted_out': _date(p.plantedOutOn),
  'finished': _date(p.finishedOn),
  'count': p.count,
  'location': p.location,
  'notes': p.notes,
  'layer': ?p.layerId,
};

/// Throws [FormatException] when a value cannot be read.
Planting plantingFromJson(Object? raw) {
  final j = _map(raw, 'planting');
  return Planting(
    id: _string(j['id'], 'planting ID'),
    varietyId: _string(j['variety'], 'planting variety'),
    sownOn:
        _readDate(j['sown'], 'sowing date') ??
        (throw const FormatException('a planting has no sowing date')),
    startedIndoors:
        _bool(j['indoors'], 'indoors') ??
        (throw const FormatException('a planting does not say where')),
    plantedOutOn: _readDate(j['planted_out'], 'planting-out date'),
    finishedOn: _readDate(j['finished'], 'finishing date'),
    count: _optionalInt(j['count'], 'planting count'),
    location: _optionalString(j['location'], 'planting location') ?? '',
    notes: _optionalString(j['notes'], 'planting notes') ?? '',
    layerId: _optionalString(j['layer'], 'planting layer'),
  );
}

String? _date(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

DateTime? _readDate(Object? raw, String what) {
  if (raw == null) return null;
  final parsed = raw is String ? DateTime.tryParse(raw) : null;
  if (parsed == null) throw FormatException('$what is not readable');
  return dayOf(parsed);
}

// ---------------------------------------------------------------- readers

Map<String, Object?> _map(Object? value, String what) {
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('$what is not readable');
}

List<Object?> _list(Object? value, String what) {
  if (value == null) return const [];
  if (value is List) return value;
  throw FormatException('$what is not readable');
}

String _string(Object? value, String what) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('$what is not readable');
}

String? _optionalString(Object? value, String what) {
  if (value == null || value is String) return value as String?;
  throw FormatException('$what is not readable');
}

int? _optionalInt(Object? value, String what) {
  if (value == null || value is int) return value as int?;
  throw FormatException('$what is not readable');
}

int _count(Object? value, String what) {
  if (value is int && value >= 0) return value;
  throw FormatException('$what is not readable');
}

bool? _bool(Object? value, String what) {
  if (value == null || value is bool) return value as bool?;
  throw FormatException('$what is not readable');
}

T? _optionalEnum<T extends Enum>(List<T> values, Object? name, String what) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('unknown $what "$name"');
}

HardinessZone _zone(Object? value) {
  if (value == null) return HardinessZone.fallback;
  return HardinessZone.tryParse(value) ??
      (throw FormatException('unknown hardiness zone "$value"'));
}

MonthDay? _monthDay(Object? value) {
  if (value == null) return null;
  return MonthDay.tryParse(value) ??
      (throw FormatException('a frost date is not readable'));
}

/// The items keyed by ID, refusing a second item with the same ID.
Map<String, T> _unique<T>(List<T> items, String Function(T) idOf, String what) {
  final byId = <String, T>{};
  for (final item in items) {
    if (byId.containsKey(idOf(item))) {
      throw FormatException('$what ${idOf(item)} appears twice');
    }
    byId[idOf(item)] = item;
  }
  return byId;
}

int _idNumber(String id) =>
    int.tryParse(id.substring(id.lastIndexOf('-') + 1)) ?? 0;
