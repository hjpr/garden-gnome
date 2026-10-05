import 'dart:typed_data';

/// A .ggnome file on disk that the app can read again later, e.g. at
/// start-up, and write back to on Save. What it holds depends on the
/// platform: a browser file handle, or a path on desktop.
abstract interface class FarmFileRef {
  /// The file name, e.g. "Home farm.ggnome".
  String get name;
}

/// A file read from disk. [ref] is null when the platform can only read
/// the file once (browsers without file handles, such as Firefox).
class OpenedFarmFile {
  const OpenedFarmFile(this.bytes, this.name, this.ref);

  final Uint8List bytes;
  final String name;
  final FarmFileRef? ref;
}

/// What reopening the remembered file found.
sealed class Reopened {
  const Reopened();
}

/// Nothing remembered, or the file is gone: start with an empty farm.
class NothingToReopen extends Reopened {
  const NothingToReopen();
}

class ReopenedFile extends Reopened {
  const ReopenedFile(this.file);

  final OpenedFarmFile file;
}

/// The file is still there but the browser wants the user's go-ahead,
/// which it only accepts after a click.
class ReopenNeedsPermission extends Reopened {
  const ReopenNeedsPermission(this.name);

  final String name;
}

/// Reading and writing .ggnome files where they live on disk, and
/// remembering the last one for next time.
///
/// Storage failures throw StorageError. A cancelled picker returns null.
abstract interface class FarmFiles {
  /// Whether Save can write straight back to the opened file (Chrome and
  /// Edge, and desktop). Elsewhere the farm is saved in the browser and a
  /// file is only a download.
  bool get savesInPlace;

  /// Whether farms can also be kept in the browser's own library (web).
  /// On desktop the files on disk are the library.
  bool get hasBrowserLibrary;

  /// Asks the user for a .ggnome file to open.
  Future<OpenedFarmFile?> pickToOpen();

  /// Asks where to save [bytes] as a new file, named [suggestedName] by
  /// default, and writes it. Only when [savesInPlace].
  Future<FarmFileRef?> pickToSave(String suggestedName, Uint8List bytes);

  /// Writes [bytes] over the file [ref].
  Future<void> write(FarmFileRef ref, Uint8List bytes);

  /// Remembers [ref] to reopen at start-up; null forgets.
  Future<void> remember(FarmFileRef? ref);

  /// The remembered file's name, or null.
  Future<String?> rememberedName();

  /// Reads the remembered file. With [ask] the browser may show its
  /// permission prompt, so call it straight from a click.
  Future<Reopened> reopen({bool ask = false});

  /// Saves [bytes] as a standalone copy named [name]: a download in the
  /// browser, a save dialog on desktop.
  Future<void> exportCopy(String name, Uint8List bytes);
}
