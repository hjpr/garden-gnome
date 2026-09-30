import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

import '../application/document_storage.dart';
import '../application/storage_error.dart';
import '../domain/document.dart';
import 'document_codec.dart';

export '../application/document_storage.dart' show DrawingLibrary, LibraryEntry;
export '../application/storage_error.dart';

/// Drawings saved in this browser with IndexedDB.
///
/// This is local to the browser profile and is not a backup: clearing site
/// data removes it. Use Export to keep a portable copy.
class BrowserDrawingLibrary implements DrawingLibrary {
  BrowserDrawingLibrary({IdbFactory? factory})
    : _factory = factory ?? idbFactoryBrowser;

  static const _databaseName = 'garden_gnome';
  static const _store = 'drawings';

  final IdbFactory _factory;
  Database? _database;

  Future<Database> _open() async {
    return _database ??= await _factory.open(
      _databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        if (!event.database.objectStoreNames.contains(_store)) {
          event.database.createObjectStore(_store);
        }
      },
    );
  }

  @override
  Future<List<LibraryEntry>> list() async {
    try {
      final db = await _open();
      final txn = db.transaction(_store, idbModeReadOnly);
      final records = await txn.objectStore(_store).getAll();
      await txn.completed;
      final entries = [
        for (final record in records.cast<Map>())
          LibraryEntry(
            id: record['id'] as String,
            title: record['title'] as String,
            savedAt: DateTime.fromMillisecondsSinceEpoch(
              record['saved_at'] as int,
            ),
          ),
      ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return entries;
    } catch (_) {
      throw const StorageError('Could not read drawings saved in this browser');
    }
  }

  @override
  Future<void> save(String id, String title, GardenDocument document) async {
    try {
      final bytes = encodeGgnome(document);
      final db = await _open();
      final txn = db.transaction(_store, idbModeReadWrite);
      await txn.objectStore(_store).put({
        'id': id,
        'title': title,
        'saved_at': DateTime.now().millisecondsSinceEpoch,
        'data': bytes,
      }, id);
      await txn.completed;
      final written = await _readBytes(id);
      if (written == null || !_sameBytes(written, bytes)) {
        throw const StorageError('The saved copy could not be confirmed');
      }
    } on StorageError {
      rethrow;
    } catch (_) {
      throw const StorageError(
        'Could not save in this browser. Storage may be full or blocked. '
        'Your drawing is still open; try again or use Export.',
      );
    }
  }

  @override
  Future<GardenDocument> open(String id) async {
    final Uint8List? bytes;
    try {
      bytes = await _readBytes(id);
    } catch (_) {
      throw const StorageError('Could not read that drawing');
    }
    if (bytes == null) {
      throw const StorageError('That drawing no longer exists');
    }
    return decodeGgnome(bytes);
  }

  @override
  Future<void> delete(String id) async {
    try {
      final db = await _open();
      final txn = db.transaction(_store, idbModeReadWrite);
      await txn.objectStore(_store).delete(id);
      await txn.completed;
    } catch (_) {
      throw const StorageError('Could not delete that drawing');
    }
  }

  Future<Uint8List?> _readBytes(String id) async {
    final db = await _open();
    final txn = db.transaction(_store, idbModeReadOnly);
    final record = await txn.objectStore(_store).getObject(id);
    await txn.completed;
    if (record is! Map) return null;
    final data = record['data'];
    if (data is Uint8List) return data;
    if (data is List) return Uint8List.fromList(data.cast<int>());
    return null;
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
