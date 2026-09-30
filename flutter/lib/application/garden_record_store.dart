import '../domain/grow/garden_record.dart';

export 'storage_error.dart' show GardenRecordFormatError;

/// Where the Seed Vault, plantings and climate are kept between sessions.
///
/// The growing tools own this contract; the browser adapter lives in
/// persistence and is handed in at start-up.
abstract interface class GardenRecordStore {
  /// The stored record, or an empty one when nothing is stored yet.
  /// Throws when a stored record cannot be read, so the caller can keep
  /// it rather than write over it.
  Future<GardenRecord> load();

  Future<void> save(GardenRecord record);
}
