import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/farm_files.dart';
import '../application/storage_error.dart';

/// Desktop: farms are ordinary files, remembered by path.
FarmFiles createFarmFiles() => _IoFarmFiles();

const _group = XTypeGroup(label: 'Garden Gnome farm', extensions: ['ggnome']);

class _PathRef implements FarmFileRef {
  const _PathRef(this.path);

  final String path;

  @override
  String get name => path.split(Platform.pathSeparator).last;
}

class _IoFarmFiles implements FarmFiles {
  static const _key = 'garden_gnome.last_file';

  @override
  bool get savesInPlace => true;

  @override
  bool get hasBrowserLibrary => false;

  @override
  Future<OpenedFarmFile?> pickToOpen() async {
    final file = await openFile(acceptedTypeGroups: const [_group]);
    if (file == null) return null;
    final ref = _PathRef(file.path);
    return OpenedFarmFile(await _read(ref), ref.name, ref);
  }

  @override
  Future<FarmFileRef?> pickToSave(String suggestedName, Uint8List bytes) async {
    final where = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [_group],
    );
    if (where == null) return null;
    final path = where.path.endsWith('.ggnome')
        ? where.path
        : '${where.path}.ggnome';
    final ref = _PathRef(path);
    await write(ref, bytes);
    return ref;
  }

  @override
  Future<void> write(FarmFileRef ref, Uint8List bytes) async {
    final path = (ref as _PathRef).path;
    // Written beside the file and then swapped in, so a failed save never
    // leaves half a farm on disk.
    final temporary = File('$path.saving');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(path);
    } on FileSystemException catch (e) {
      try {
        await temporary.delete();
      } catch (_) {}
      throw StorageError(
        'Could not save ${ref.name}: ${e.osError?.message ?? e.message}',
      );
    }
  }

  Future<Uint8List> _read(_PathRef ref) async {
    try {
      return await File(ref.path).readAsBytes();
    } on FileSystemException catch (e) {
      throw StorageError(
        'Could not open ${ref.name}: ${e.osError?.message ?? e.message}',
      );
    }
  }

  @override
  Future<void> remember(FarmFileRef? ref) async {
    final prefs = await SharedPreferences.getInstance();
    if (ref == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, (ref as _PathRef).path);
    }
  }

  Future<_PathRef?> _remembered() async {
    final path = (await SharedPreferences.getInstance()).getString(_key);
    return path == null ? null : _PathRef(path);
  }

  @override
  Future<String?> rememberedName() async => (await _remembered())?.name;

  @override
  Future<Reopened> reopen({bool ask = false}) async {
    final ref = await _remembered();
    if (ref == null || !await File(ref.path).exists()) {
      return const NothingToReopen();
    }
    return ReopenedFile(OpenedFarmFile(await _read(ref), ref.name, ref));
  }

  @override
  Future<void> exportCopy(String name, Uint8List bytes) async {
    await pickToSave(name, bytes);
  }
}
