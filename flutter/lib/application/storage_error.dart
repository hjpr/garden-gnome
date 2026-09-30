/// A storage operation failed. The message can be shown to the user.
class StorageError implements Exception {
  const StorageError(this.message);

  final String message;

  @override
  String toString() => message;
}

class DocumentFormatError implements Exception {
  const DocumentFormatError(this.message);

  final String message;

  @override
  String toString() => message;
}

class GardenRecordFormatError implements Exception {
  const GardenRecordFormatError(this.message);

  final String message;

  @override
  String toString() => message;
}
