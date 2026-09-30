import 'package:shared_preferences/shared_preferences.dart';

import '../application/garden_record_store.dart';
import '../application/storage_error.dart';
import '../domain/grow/garden_record.dart';
import 'garden_record_codec.dart';

/// The garden record in this browser's local storage. Small (text only),
/// so it is kept whole under one key and rewritten on every change.
class BrowserGardenRecordStore implements GardenRecordStore {
  static const _key = 'garden_gnome.garden_record';

  @override
  Future<GardenRecord> load() async {
    final String? raw;
    try {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_key);
    } catch (_) {
      throw const StorageError(
        'Could not read the garden record in this browser',
      );
    }
    return raw == null ? GardenRecord() : decodeGardenRecord(raw);
  }

  @override
  Future<void> save(GardenRecord record) async {
    try {
      final raw = encodeGardenRecord(record);
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_key, raw)) {
        throw const StorageError(
          'Could not save the garden record in this browser',
        );
      }
    } catch (_) {
      throw const StorageError(
        'Could not save the garden record in this browser',
      );
    }
  }
}
