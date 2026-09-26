/// Text typed into a Properties field that has not been applied yet.
class PropertyDraft {
  PropertyDraft({
    required this.layerId,
    required this.text,
    required this.committedText,
    required this.check,
    required this.apply,
    this.isRename = false,
  });

  /// The layer the value belongs to, captured when typing began.
  final String layerId;
  final String text;
  final String committedText;

  /// Returns a reason the text is not acceptable, or null.
  final String? Function(String text) check;

  /// Writes the accepted text to the owning layer.
  final void Function(String text) apply;

  /// Renames apply only through Save name / Cancel.
  final bool isRename;

  bool get changed => text != committedText;
  String? get problem => check(text);
}

/// Every unapplied Properties draft, keyed by field.
///
/// Drafts settle in a few defined moments (Enter, blur, switching layer,
/// saving) rather than as a side effect of focus order.
class DraftRegistry {
  final Map<String, PropertyDraft> _drafts = {};

  /// Called whenever drafts are applied or dropped, so fields can refresh.
  void Function()? onChanged;

  PropertyDraft? operator [](String key) => _drafts[key];

  bool get hasUnappliedChanges => _drafts.values.any((d) => d.changed);

  void update(String key, PropertyDraft draft) {
    if (draft.changed) {
      _drafts[key] = draft;
    } else {
      _drafts.remove(key);
    }
  }

  /// Applies one draft if valid. Returns the problem when it is not.
  String? commit(String key) {
    final draft = _drafts[key];
    if (draft == null) return null;
    final problem = draft.problem;
    if (problem != null) return problem;
    _drafts.remove(key);
    draft.apply(draft.text);
    onChanged?.call();
    return null;
  }

  void discard(String key) {
    if (_drafts.remove(key) != null) onChanged?.call();
  }

  /// Before switching layers or closing Properties: apply valid ordinary
  /// drafts to their owner and drop invalid ones and unsaved renames.
  void settleForLayerSwitch() {
    if (_drafts.isEmpty) return;
    final pending = Map.of(_drafts);
    _drafts.clear();
    for (final draft in pending.values) {
      if (!draft.isRename && draft.problem == null) draft.apply(draft.text);
    }
    onChanged?.call();
  }

  void discardForLayers(Set<String> layerIds) {
    final before = _drafts.length;
    _drafts.removeWhere((_, draft) => layerIds.contains(draft.layerId));
    if (_drafts.length != before) onChanged?.call();
  }

  void clear() {
    _drafts.clear();
    onChanged?.call();
  }

  /// Before saving: every draft must be valid and no rename may be pending.
  ///
  /// Checks all drafts first so a problem leaves every draft untouched;
  /// otherwise applies them all. Returns the reason saving must wait.
  String? settleForSave() {
    for (final draft in _drafts.values) {
      if (draft.isRename) return 'Save or cancel the new layer name first';
      final problem = draft.problem;
      if (problem != null) return 'Fix the highlighted property: $problem';
    }
    settleForLayerSwitch();
    return null;
  }
}
