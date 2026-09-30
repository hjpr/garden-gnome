import 'dart:typed_data';

import '../domain/document.dart';
import 'camera.dart';
import 'workspace_settings.dart';

export 'storage_error.dart' show DocumentFormatError;

class LibraryEntry {
  const LibraryEntry({
    required this.id,
    required this.title,
    required this.savedAt,
  });

  final String id;
  final String title;
  final DateTime savedAt;
}

/// Storage failures throw StorageError; damaged drawings throw
/// DocumentFormatError. A missing workspace is not a damaged drawing.
abstract interface class DrawingLibrary {
  Future<List<LibraryEntry>> list();

  /// Returns only after the stored copy has been confirmed.
  Future<void> save(String id, String title, GardenDocument document);

  Future<GardenDocument> open(String id);
  Future<void> delete(String id);
}

abstract interface class DocumentCodec {
  Uint8List encode(GardenDocument document);
  GardenDocument decode(Uint8List bytes);
}

abstract interface class WorkspaceStorage {
  Future<(WorkspaceSettings, Camera)?> load(String documentId);
  Future<CounterLedger> counters(String documentId);
  Future<void> save(
    String documentId,
    WorkspaceSettings settings,
    Camera camera,
    CounterLedger ledger,
  );
}
