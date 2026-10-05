import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/document.dart';
import 'camera.dart';
import 'document_storage.dart';
import 'editor_controller.dart';
import 'farm_files.dart';
import 'identifiers.dart';
import 'storage_error.dart';
import 'toasts.dart';
import 'workspace_settings.dart';

/// The outcome of a file command, for the screen to report.
sealed class CommandResult {
  const CommandResult();
}

class Succeeded extends CommandResult {
  const Succeeded([this.message]);

  final String? message;
}

/// The user must act first, e.g. finish a rename. Nothing was changed.
class NeedsAttention extends CommandResult {
  const NeedsAttention(this.message);

  final String message;
}

class Failed extends CommandResult {
  const Failed(this.message);

  final String message;
}

/// Owns the open drawing and runs New, Open, Save, Save as, and Import.
///
/// Each command settles Properties drafts the same way whether it comes
/// from a menu or a keyboard shortcut. Open and Import load into a separate
/// document and only replace the current one once it has passed every check.
class DocumentSession extends ChangeNotifier {
  DocumentSession({
    required this.library,
    required this.workspace,
    required this.codec,
    this.lastFarm,
    this.files,
    EditorController? editor,
  }) : toasts = editor?.toasts ?? ToastCenter() {
    _editor = editor ?? EditorController(toasts: toasts);
  }

  final DrawingLibrary library;
  final WorkspaceStorage workspace;
  final DocumentCodec codec;
  final LastFarmStore? lastFarm;

  /// .ggnome files on disk. With [FarmFiles.savesInPlace], Save writes
  /// back to the file a farm came from, and the last file reopens at
  /// start-up.
  final FarmFiles? files;

  /// Whether Save and Save as go to files on disk rather than the browser
  /// library.
  bool get savesToFiles => files?.savesInPlace ?? false;

  /// The remembered file's name while the browser waits for a click before
  /// it lets the app read it again; null otherwise.
  String? get reopenWaiting => _reopenWaiting;
  String? _reopenWaiting;

  Future<void> _saveTail = Future.value();
  (EditorController editor, String id, int sequence)? _pendingSave;
  int _saveSequence = 0;

  /// Toasts outlive any one drawing, so one raised just before New or
  /// Open is still seen afterwards.
  final ToastCenter toasts;

  late EditorController _editor;
  EditorController get editor => _editor;

  /// Whether leaving now would lose typed or drawn work.
  bool get hasUnsavedWork =>
      _editor.isDirty ||
      _editor.drafts.hasUnappliedChanges ||
      _editor.preferencesPending;

  /// Applies valid Properties drafts, or explains what needs attention.
  CommandResult? _settleDrafts() {
    if (_editor.preferencesPending) {
      return const NeedsAttention('Apply or close Preferences before saving');
    }
    final problem = _editor.drafts.settleForSave();
    return problem == null ? null : NeedsAttention(problem);
  }

  /// Saves to the file the farm came from, or to the browser library
  /// under its current identity; a farm saved nowhere yet needs Save as.
  Future<CommandResult> save() async {
    if (_editor.fileRef case final ref? when savesToFiles) {
      final blocked = _settleDrafts();
      if (blocked != null) return blocked;
      return _writeFile(ref);
    }
    final pending = _pendingSave;
    final id = pending != null && identical(pending.$1, _editor)
        ? pending.$2
        : _editor.libraryId;
    if (id == null) return saveAs(_editor.title);
    final blocked = _settleDrafts();
    if (blocked != null) return blocked;
    return _write(_editor.document.withId(id), id, _editor.title);
  }

  /// Saves as a new drawing with its own identity. The drawing takes the
  /// new name at once, so a rename made while the copy is written is a
  /// further change rather than lost.
  Future<CommandResult> saveAs(String title) async {
    final blocked = _settleDrafts();
    if (blocked != null) return blocked;
    final name = title.trim().isEmpty ? 'Untitled' : title.trim();
    _editor.renameDrawing(name);
    final copy = _editor.document.withId(newUuid());
    return _write(copy, copy.id, name);
  }

  /// Saves to a new file the user picks. Null when the picker is closed.
  Future<CommandResult?> saveAsFile() async {
    final blocked = _settleDrafts();
    if (blocked != null) return blocked;
    final suggested =
        '${_editor.title.replaceAll(RegExp(r'[^\w\- ]'), '_')}'
        '.ggnome';
    final editor = _editor;
    final snapshot = editor.document;
    try {
      final ref = await files!.pickToSave(suggested, codec.encode(snapshot));
      if (ref == null) return null;
      final title = ref.name.replaceFirst(RegExp(r'\.ggnome$'), '');
      if (identical(editor, _editor)) {
        editor.renameDrawing(title);
        editor.markSaved(snapshot, fileRef: ref, title: title);
        await _rememberFile(ref);
        notifyListeners();
      }
      return Succeeded('Saved ${ref.name}');
    } on StorageError catch (e) {
      return Failed(e.message);
    }
  }

  Future<CommandResult> _writeFile(FarmFileRef ref) async {
    final editor = _editor;
    final snapshot = editor.document;
    final previous = _saveTail;
    final finished = Completer<void>();
    _saveTail = finished.future;
    try {
      await previous;
      await files!.write(ref, codec.encode(snapshot));
      if (identical(editor, _editor)) {
        editor.markSaved(snapshot, fileRef: ref);
        await _rememberFile(ref);
        await _rememberWorkspace();
        notifyListeners();
      }
      return Succeeded('Saved ${ref.name}');
    } on StorageError catch (e) {
      return Failed(e.message);
    } finally {
      finished.complete();
    }
  }

  /// The last farm is either a file or a library entry: remembering one
  /// forgets the other, so the most recent wins at start-up.
  Future<void> _rememberFile(FarmFileRef? ref) async {
    try {
      await files?.remember(ref);
      if (ref != null) await lastFarm?.save(null);
    } catch (_) {
      // Only start-up convenience is lost.
    }
  }

  /// Writes [snapshot] and, if the same drawing is still open when the
  /// write finishes, records it as saved. Edits made in the meantime stay
  /// and keep the drawing marked unsaved; a drawing opened in the
  /// meantime is left alone, the copy being safe in the library.
  Future<CommandResult> _write(
    GardenDocument snapshot,
    String id,
    String title,
  ) async {
    final editor = _editor;
    final sequence = ++_saveSequence;
    _pendingSave = (editor, id, sequence);
    final previous = _saveTail;
    final finished = Completer<void>();
    _saveTail = finished.future;
    try {
      // Serialize writes, not editing: each request keeps its own snapshot.
      await previous;
      await library.save(id, title, snapshot);
      final message = Succeeded('Saved “$title” in this browser');
      if (!identical(editor, _editor)) return message;
      if (snapshot.id != editor.document.id) editor.adoptIdentity(snapshot.id);
      editor.markSaved(snapshot, libraryId: id, title: title);
      await _rememberFile(null);
      await _rememberLastFarm(id);
      await _rememberWorkspace();
      notifyListeners();
      return message;
    } on StorageError catch (e) {
      return Failed(e.message);
    } on DocumentFormatError catch (e) {
      return Failed(e.message);
    } finally {
      if (_pendingSave?.$3 == sequence) _pendingSave = null;
      finished.complete();
    }
  }

  /// Starts a fresh, empty farm.
  Future<void> newDrawing() async {
    await _rememberWorkspace();
    _replaceEditor(EditorController(toasts: toasts));
    await _rememberLastFarm(null);
    await _rememberFile(null);
    _setReopenWaiting(null);
  }

  void _setReopenWaiting(String? name) {
    if (_reopenWaiting == name) return;
    _reopenWaiting = name;
    notifyListeners();
  }

  /// Reopens the farm that was open last: the file on disk it came from
  /// if the platform can read it again, else its browser library entry.
  /// A farm that is gone or unreadable leaves the blank farm. Called once
  /// at start-up. When the browser needs a click first, [reopenWaiting]
  /// names the file and [reopenFile] finishes the job.
  Future<void> reopenLastFarm() async {
    try {
      switch (await files?.reopen()) {
        case ReopenedFile(:final file):
          if (await import(file.bytes, file.name, ref: file.ref) is Succeeded) {
            return;
          }
        case ReopenNeedsPermission(:final name):
          _setReopenWaiting(name);
          return;
        case NothingToReopen() || null:
          break;
      }
    } catch (_) {
      // Fall back to the library, then to the blank farm.
    }
    try {
      final id = await lastFarm?.load();
      if (id == null) return;
      final entry = (await library.list()).where((e) => e.id == id);
      if (entry.isEmpty) return;
      await open(entry.first);
    } catch (_) {
      // A farm that cannot be reopened leaves the blank one open.
    }
  }

  Future<void> _rememberLastFarm(String? libraryId) async {
    try {
      await lastFarm?.save(libraryId);
    } catch (_) {
      // Only start-up convenience is lost.
    }
  }

  /// Reopens the remembered file after the user agreed; call it straight
  /// from their click so the browser lets it ask for permission.
  Future<CommandResult> reopenFile() async {
    final Reopened found;
    try {
      found = await files!.reopen(ask: true);
    } on StorageError catch (e) {
      return Failed(e.message);
    }
    _setReopenWaiting(null);
    return switch (found) {
      ReopenedFile(:final file) => import(file.bytes, file.name, ref: file.ref),
      ReopenNeedsPermission(:final name) => Failed(
        'The browser did not allow reading $name',
      ),
      NothingToReopen() => const Failed('The last farm file is gone'),
    };
  }

  /// Forgets the remembered file and keeps the blank farm.
  Future<void> skipReopen() async {
    _setReopenWaiting(null);
    await _rememberFile(null);
  }

  /// Opens a drawing from the browser library.
  Future<CommandResult> open(LibraryEntry entry) async {
    final GardenDocument candidate;
    try {
      candidate = await library.open(entry.id);
      await _load(candidate, title: entry.title, libraryId: entry.id);
      await _rememberFile(null);
      await _rememberLastFarm(entry.id);
    } on StorageError catch (e) {
      return Failed(e.message);
    } on DocumentFormatError catch (e) {
      return Failed(e.message);
    }
    return const Succeeded();
  }

  /// Opens a .ggnome file. With [ref] Save writes back to it and it
  /// reopens at start-up; without, it is not saved anywhere until Save as.
  Future<CommandResult> import(
    Uint8List bytes,
    String fileName, {
    FarmFileRef? ref,
  }) async {
    final GardenDocument candidate;
    try {
      candidate = codec.decode(bytes);
      final title = fileName.replaceFirst(RegExp(r'\.ggnome$'), '');
      await _load(candidate, title: title, libraryId: null, fileRef: ref);
      await _rememberLastFarm(null);
      await _rememberFile(ref);
    } on DocumentFormatError catch (e) {
      return Failed(e.message);
    } on StorageError catch (e) {
      return Failed(e.message);
    }
    return const Succeeded();
  }

  /// The current drawing as a portable .ggnome file.
  Uint8List export() => codec.encode(_editor.document);

  Future<void> _load(
    GardenDocument candidate, {
    required String title,
    required String? libraryId,
    FarmFileRef? fileRef,
  }) async {
    await _rememberWorkspace();
    final ledger = await workspace.counters(candidate.id);
    final stored = await workspace.load(candidate.id);
    final raised = candidate.withCounterFloor(ledger);
    // An imported file matches what is on disk, so it starts unchanged;
    // it has no library entry, so its first Save asks for a name.
    final editor = EditorController(
      document: raised,
      settings: stored?.$1 ?? const WorkspaceSettings(),
      camera: stored?.$2 ?? const Camera(),
      fitOnFirstView: stored == null,
      title: title,
      libraryId: libraryId,
      fileRef: fileRef,
      toasts: toasts,
    );
    editor.ledger.merge(ledger);
    _replaceEditor(editor);
  }

  void _replaceEditor(EditorController next) {
    final old = _editor;
    _editor = next;
    notifyListeners();
    old.dispose();
  }

  Future<void> _rememberWorkspace() async {
    try {
      await workspace.save(
        _editor.document.id,
        _editor.settings,
        _editor.camera,
        _editor.ledger,
      );
    } on StorageError catch (e) {
      // A local view failure must not undo a confirmed drawing save.
      toasts.show(e.message, kind: ToastKind.error);
    }
  }

  /// Stores the current view and settings, e.g. when the page is hidden.
  Future<void> rememberWorkspace() => _rememberWorkspace();
}
