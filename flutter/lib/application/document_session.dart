import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/document.dart';
import 'camera.dart';
import 'document_storage.dart';
import 'editor_controller.dart';
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
    EditorController? editor,
  }) : toasts = editor?.toasts ?? ToastCenter() {
    _editor = editor ?? EditorController(toasts: toasts);
  }

  final DrawingLibrary library;
  final WorkspaceStorage workspace;
  final DocumentCodec codec;

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

  /// Saves to the browser library under the drawing's current identity.
  Future<CommandResult> save() async {
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

  /// Starts a fresh, empty drawing.
  Future<void> newDrawing() async {
    await _rememberWorkspace();
    _replaceEditor(EditorController(toasts: toasts));
  }

  /// Opens a drawing from the browser library.
  Future<CommandResult> open(LibraryEntry entry) async {
    final GardenDocument candidate;
    try {
      candidate = await library.open(entry.id);
      await _load(candidate, title: entry.title, libraryId: entry.id);
    } on StorageError catch (e) {
      return Failed(e.message);
    } on DocumentFormatError catch (e) {
      return Failed(e.message);
    }
    return const Succeeded();
  }

  /// Opens a .ggnome file. It is not in the library until saved.
  Future<CommandResult> import(Uint8List bytes, String fileName) async {
    final GardenDocument candidate;
    try {
      candidate = codec.decode(bytes);
      final title = fileName.replaceFirst(RegExp(r'\.ggnome$'), '');
      await _load(candidate, title: title, libraryId: null);
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
