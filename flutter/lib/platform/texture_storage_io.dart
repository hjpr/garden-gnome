import 'dart:io';

import 'package:idb_shim/idb_io.dart';

/// A database in the app's data folder, so installed textures outlive the
/// session: $XDG_DATA_HOME (or ~/.local/share) on Linux, Application
/// Support on macOS, %APPDATA% on Windows. Falls back to memory when no
/// home folder is known.
IdbFactory textureStorageFactory() {
  final env = Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'];
  final String? base;
  if (Platform.isWindows) {
    base = env['APPDATA'] ?? home;
  } else if (Platform.isMacOS) {
    base = home == null ? null : '$home/Library/Application Support';
  } else {
    base = env['XDG_DATA_HOME'] ?? (home == null ? null : '$home/.local/share');
  }
  if (base == null) return idbFactorySembastMemory;
  final folder = Directory('$base${Platform.pathSeparator}garden_gnome');
  folder.createSync(recursive: true);
  return getIdbFactorySembastIo(folder.path);
}
