import 'package:garden_gnome/application/garden_record_store.dart';
import 'package:garden_gnome/domain/grow/garden_record.dart';
import 'package:garden_gnome/persistence/garden_record_codec.dart';

/// Keeps the record in memory, through the real codec, so tests see what
/// a browser would store.
class MemoryGardenRecordStore implements GardenRecordStore {
  MemoryGardenRecordStore([GardenRecord? record])
    : _saved = record == null ? null : encodeGardenRecord(record);

  /// Starts with [text] already stored, readable or not.
  MemoryGardenRecordStore.holding(String text) : _saved = text;

  String? _saved;
  int saves = 0;

  /// What is stored now, as written.
  String? get storedText => _saved;

  @override
  Future<GardenRecord> load() async =>
      _saved == null ? GardenRecord() : decodeGardenRecord(_saved!);

  @override
  Future<void> save(GardenRecord record) async {
    saves++;
    _saved = encodeGardenRecord(record);
  }
}
