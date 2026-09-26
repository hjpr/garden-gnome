import 'package:flutter/foundation.dart';

import '../domain/document.dart';
import '../persistence/document_codec.dart';
import '../persistence/drawing_library.dart';
import '../persistence/workspace_store.dart';
import 'camera.dart';
import 'editor_controller.dart';
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
    EditorController? editor,
  }) : toasts = editor?.toasts ?? ToastCenter() {
    _editor = editor ?? EditorController(toasts: toasts);
  }

  final DrawingLibrary library;
  final WorkspaceStore workspace;

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
    if (_editor.libraryId == null) return saveAs(_editor.title);
    final blocked = _settleDrafts();
    if (blocked != null) return blocked;
    return _write(_editor.document, _editor.libraryId!, _editor.title);
  }

  /// Saves as a new drawing with its own identity.
  Future<CommandResult> saveAs(String title) async {
    final blocked = _settleDrafts();
    if (blocked != null) return blocked;
    final copy = _editor.document.withId(newUuid());
    return _write(
      copy,
      copy.id,
      title.trim().isEmpty ? 'Untitled' : title.trim(),
    );
  }

  Future<CommandResult> _write(
    GardenDocument snapshot,
    String id,
    String title,
  ) async {
    try {
      await library.save(id, title, snapshot);
    } on StorageError catch (e) {
      return Failed(e.message);
    }
    final previousId = _editor.document.id;
    if (snapshot.id != previousId) {
      _editor.replaceDocumentIdentity(snapshot);
    }
    _editor.markSaved(snapshot, libraryId: id, title: title);
    await _rememberWorkspace();
    notifyListeners();
    return Succeeded('Saved “$title” in this browser');
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
    } on StorageError catch (e) {
      return Failed(e.message);
    } on DocumentFormatError catch (e) {
      return Failed(e.message);
    }
    await _load(candidate, title: entry.title, libraryId: entry.id);
    return const Succeeded();
  }

  /// Opens a .ggnome file. It is not in the library until saved.
  Future<CommandResult> import(Uint8List bytes, String fileName) async {
    final GardenDocument candidate;
    try {
      candidate = decodeGgnome(bytes);
    } on DocumentFormatError catch (e) {
      return Failed(e.message);
    }
    final title = fileName.replaceFirst(RegExp(r'\.ggnome$'), '');
    await _load(candidate, title: title, libraryId: null);
    return const Succeeded();
  }

  /// The current drawing as a portable .ggnome file.
  Uint8List export() => encodeGgnome(_editor.document);

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

  Future<void> _rememberWorkspace() => workspace.save(
    _editor.document.id,
    _editor.settings,
    _editor.camera,
    _editor.ledger,
  );

  /// Stores the current view and settings, e.g. when the page is hidden.
  Future<void> rememberWorkspace() => _rememberWorkspace();
}
