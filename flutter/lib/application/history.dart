import '../domain/document.dart';

/// Where a live Line drawing was before and after an action, so Undo and
/// Redo inside the same drawing can put the dashed preview back.
class LineContext {
  const LineContext({
    required this.operation,
    this.anchorBefore,
    this.anchorAfter,
  });

  /// Identifies the live drawing operation that produced the action.
  final int operation;
  final String? anchorBefore;
  final String? anchorAfter;
}

/// One undoable change.
///
/// Documents are immutable and share unchanged layers, so keeping the
/// document from before and after the change is cheap and restores exact
/// identities, ownership, and order.
class HistoryEntry {
  const HistoryEntry({
    required this.label,
    required this.before,
    required this.after,
    this.lineContext,
  });

  final String label;
  final GardenDocument before;
  final GardenDocument after;
  final LineContext? lineContext;
}

/// Undo and Redo stacks that together hold at most [capacity] entries.
class History {
  History({this.capacity = 50});

  int capacity;
  final List<HistoryEntry> _undo = [];
  final List<HistoryEntry> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  HistoryEntry? get undoEntry => _undo.lastOrNull;
  HistoryEntry? get redoEntry => _redo.lastOrNull;
  String? get undoLabel => canUndo ? _undo.last.label : null;
  String? get redoLabel => canRedo ? _redo.last.label : null;

  /// Records a new change. Clears Redo and drops the oldest entries when full.
  void record(HistoryEntry entry) {
    _redo.clear();
    _undo.add(entry);
    _trim();
  }

  HistoryEntry? takeUndo() {
    if (_undo.isEmpty) return null;
    final entry = _undo.removeLast();
    _redo.add(entry);
    return entry;
  }

  HistoryEntry? takeRedo() {
    if (_redo.isEmpty) return null;
    final entry = _redo.removeLast();
    _undo.add(entry);
    return entry;
  }

  void resize(int newCapacity) {
    capacity = newCapacity;
    _trim();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  /// Removes the oldest Undo entries first, then the furthest Redo entries.
  void _trim() {
    while (_undo.length + _redo.length > capacity) {
      if (_undo.isNotEmpty) {
        _undo.removeAt(0);
      } else {
        _redo.removeAt(0);
      }
    }
  }
}
