import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:web/web.dart' as web;

import '../application/farm_files.dart';
import '../application/storage_error.dart';
import 'save_copy_web.dart';

/// Browser: Chrome and Edge keep a lasting handle to the file (File System
/// Access API), stored in IndexedDB so it survives closing the browser.
/// Other browsers (Firefox) can only read a file the user picks, once.
FarmFiles createFarmFiles() =>
    _hasFileHandles ? _HandleFarmFiles() : _PickOnceFarmFiles();

bool get _hasFileHandles => web.window.has('showOpenFilePicker');

const _group = XTypeGroup(label: 'Garden Gnome farm', extensions: ['ggnome']);

@JS('showOpenFilePicker')
external JSPromise<JSArray<web.FileSystemFileHandle>> _showOpenFilePicker(
  JSObject options,
);

@JS('showSaveFilePicker')
external JSPromise<web.FileSystemFileHandle> _showSaveFilePicker(
  JSObject options,
);

/// The picker options both pickers share: .ggnome files only.
JSObject _pickerOptions({String? suggestedName}) {
  final accept = JSObject()
    ..['application/octet-stream'] = ['.ggnome'.toJS].toJS;
  final type = JSObject()
    ..['description'] = 'Garden Gnome farm'.toJS
    ..['accept'] = accept;
  final options = JSObject()
    ..['types'] = [type].toJS
    ..['excludeAcceptAllOption'] = false.toJS
    // Open and save start in the same folder each time.
    ..['id'] = 'garden-gnome-farms'.toJS;
  if (suggestedName != null) options['suggestedName'] = suggestedName.toJS;
  return options;
}

/// The user closed the picker: the browser rejects with an AbortError
/// (a DOMException, which reaches Dart as an opaque object).
bool _isAbort(Object e) => e.toString().contains('AbortError');

class _HandleRef implements FarmFileRef {
  const _HandleRef(this.handle);

  final web.FileSystemFileHandle handle;

  @override
  String get name => handle.name;
}

class _HandleFarmFiles implements FarmFiles {
  @override
  bool get savesInPlace => true;

  @override
  bool get hasBrowserLibrary => true;

  @override
  Future<OpenedFarmFile?> pickToOpen() async {
    final JSArray<web.FileSystemFileHandle> picked;
    try {
      picked = await _showOpenFilePicker(_pickerOptions()).toDart;
    } catch (e) {
      if (_isAbort(e)) return null;
      rethrow;
    }
    final handle = picked.toDart.single;
    return OpenedFarmFile(await _read(handle), handle.name, _HandleRef(handle));
  }

  @override
  Future<FarmFileRef?> pickToSave(String suggestedName, Uint8List bytes) async {
    final web.FileSystemFileHandle handle;
    try {
      handle = await _showSaveFilePicker(
        _pickerOptions(suggestedName: suggestedName),
      ).toDart;
    } catch (e) {
      if (_isAbort(e)) return null;
      rethrow;
    }
    final ref = _HandleRef(handle);
    await write(ref, bytes);
    return ref;
  }

  @override
  Future<void> write(FarmFileRef ref, Uint8List bytes) async {
    final handle = (ref as _HandleRef).handle;
    if (!await _permitted(handle, ask: true)) {
      throw StorageError('No permission to save ${handle.name}');
    }
    try {
      // The browser writes to a copy and swaps it in on close, so a failed
      // save leaves the file as it was.
      final stream = await handle.createWritable().toDart;
      await stream.write(bytes.toJS).toDart;
      await stream.close().toDart;
    } catch (e) {
      throw StorageError('Could not save ${handle.name}: $e');
    }
  }

  Future<Uint8List> _read(web.FileSystemFileHandle handle) async {
    try {
      final file = await handle.getFile().toDart;
      return (await file.arrayBuffer().toDart).toDart.asUint8List();
    } catch (e) {
      throw StorageError('Could not open ${handle.name}: $e');
    }
  }

  /// Whether the page may read and write [handle]; with [ask] the browser
  /// may prompt, which it only allows right after a click.
  Future<bool> _permitted(
    web.FileSystemFileHandle handle, {
    required bool ask,
  }) async {
    final mode = JSObject()..['mode'] = 'readwrite'.toJS;
    Future<String> call(String method) async {
      final result = await handle
          .callMethod<JSPromise<JSString>>(method.toJS, mode)
          .toDart;
      return result.toDart;
    }

    if (await call('queryPermission') == 'granted') return true;
    if (!ask) return false;
    try {
      return await call('requestPermission') == 'granted';
    } catch (_) {
      // Called without a click: the browser refuses to ask.
      return false;
    }
  }

  @override
  Future<void> remember(FarmFileRef? ref) =>
      _HandleStore.put(ref == null ? null : (ref as _HandleRef).handle);

  @override
  Future<String?> rememberedName() async => (await _HandleStore.get())?.name;

  @override
  Future<Reopened> reopen({bool ask = false}) async {
    final web.FileSystemFileHandle? handle;
    try {
      handle = await _HandleStore.get();
    } catch (_) {
      return const NothingToReopen();
    }
    if (handle == null) return const NothingToReopen();
    if (!await _permitted(handle, ask: ask)) {
      return ReopenNeedsPermission(handle.name);
    }
    try {
      return ReopenedFile(
        OpenedFarmFile(await _read(handle), handle.name, _HandleRef(handle)),
      );
    } on StorageError {
      // Moved or deleted since: start with an empty farm.
      return const NothingToReopen();
    }
  }

  @override
  Future<void> exportCopy(String name, Uint8List bytes) =>
      _download(name, bytes);
}

/// Firefox and other browsers without file handles: a file can be read
/// when picked, and saving to disk is a download. Nothing is remembered.
class _PickOnceFarmFiles implements FarmFiles {
  @override
  bool get savesInPlace => false;

  @override
  bool get hasBrowserLibrary => true;

  @override
  Future<OpenedFarmFile?> pickToOpen() async {
    final file = await openFile(acceptedTypeGroups: const [_group]);
    if (file == null) return null;
    return OpenedFarmFile(await file.readAsBytes(), file.name, null);
  }

  @override
  Future<FarmFileRef?> pickToSave(String suggestedName, Uint8List bytes) =>
      throw UnsupportedError('This browser cannot save to a chosen file');

  @override
  Future<void> write(FarmFileRef ref, Uint8List bytes) =>
      throw UnsupportedError('This browser cannot save to a chosen file');

  @override
  Future<void> remember(FarmFileRef? ref) async {}

  @override
  Future<String?> rememberedName() async => null;

  @override
  Future<Reopened> reopen({bool ask = false}) async => const NothingToReopen();

  @override
  Future<void> exportCopy(String name, Uint8List bytes) =>
      _download(name, bytes);
}

Future<void> _download(String name, Uint8List bytes) =>
    saveCopy(name, bytes, mimeType: 'application/zip', type: _group);

/// The remembered file handle, in its own IndexedDB database. Handles can
/// only be kept by IndexedDB (they are not JSON), so this talks to it
/// directly rather than through the drawing library's wrapper.
abstract final class _HandleStore {
  static const _database = 'garden_gnome_files';
  static const _store = 'handles';
  static const _key = 'last';

  static Future<web.IDBDatabase> _open() {
    final done = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_database, 1);
    request.onupgradeneeded = (web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore(_store);
    }.toJS;
    request.onsuccess = (web.Event _) {
      done.complete(request.result as web.IDBDatabase);
    }.toJS;
    request.onerror = (web.Event _) {
      done.completeError(const StorageError('Browser storage is unavailable'));
    }.toJS;
    return done.future;
  }

  static Future<T?> _run<T extends JSAny?>(
    String mode,
    web.IDBRequest Function(web.IDBObjectStore store) action,
  ) async {
    final database = await _open();
    final done = Completer<T?>();
    final request = action(
      database.transaction(_store.toJS, mode).objectStore(_store),
    );
    request.onsuccess = (web.Event _) {
      done.complete(request.result as T?);
    }.toJS;
    request.onerror = (web.Event _) {
      done.completeError(const StorageError('Browser storage is unavailable'));
    }.toJS;
    try {
      return await done.future;
    } finally {
      database.close();
    }
  }

  static Future<void> put(web.FileSystemFileHandle? handle) => _run<JSAny?>(
    'readwrite',
    (store) =>
        handle == null ? store.delete(_key.toJS) : store.put(handle, _key.toJS),
  );

  static Future<web.FileSystemFileHandle?> get() =>
      _run<web.FileSystemFileHandle?>(
        'readonly',
        (store) => store.get(_key.toJS),
      );
}
