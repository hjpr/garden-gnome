import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../domain/document.dart';
import '../domain/feature.dart';
import '../domain/geometry_editor.dart';
import '../domain/land_rules.dart';
import '../domain/layer.dart';
import '../domain/reference_image.dart';
import '../domain/region.dart';
import '../domain/vec.dart';
import '../domain/zone_ground.dart';
import 'alignment.dart';
import 'camera.dart';
import 'construction_state.dart';
import 'document_content.dart';
import 'drafts.dart';
import 'identifiers.dart';
import 'guides.dart';
import 'history.dart';
import 'previews.dart';
import 'toasts.dart';
import 'tools.dart';
import 'workspace_settings.dart';

/// The owner recorded on Properties drafts typed for the reference image,
/// which is not a layer.
const referenceDraftOwner = 'reference-image';

/// The Build screen's state and the only place drawing changes are made.
///
/// Widgets read state from here and call its commands. Every change to the
/// drawing goes through [commit], which validates it, records it for Undo,
/// and tidies selection so nothing points at removed items.
class EditorController extends ChangeNotifier {
  EditorController({
    GardenDocument? document,
    WorkspaceSettings settings = const WorkspaceSettings(),
    Camera camera = const Camera(),
    this.title = 'Untitled',
    this.libraryId,
    ToastCenter? toasts,
    bool fitOnFirstView = false,
  }) : toasts = toasts ?? ToastCenter(),
       _document = document ?? GardenDocument(id: newUuid()),
       _settings = settings,
       _camera = camera,
       _fitOnFirstView = fitOnFirstView {
    drafts.onChanged = draftsChanged;
    _savedDocument = _document;
    _savedTitle = title;
    _ledger.record(_document);
    _history.capacity = settings.appearance.historyCapacity;
  }

  /// Short pop-up messages. Shared by every drawing opened in a session,
  /// so it is not disposed with the editor.
  final ToastCenter toasts;

  // ---------------------------------------------------------------- drawing

  GardenDocument _document;
  GardenDocument get document => _document;

  final CounterLedger _ledger = CounterLedger();
  CounterLedger get ledger => _ledger;

  final History _history = History();

  /// The name shown in the header.
  String title;

  /// Where the drawing is saved in the browser library, if it has been.
  String? libraryId;

  late GardenDocument _savedDocument;
  late String _savedTitle;

  /// Whether the drawing or its name differs from the last save.
  ///
  /// Compares content, so undoing back to the saved state counts as clean.
  bool get isDirty =>
      title != _savedTitle || !sameContent(_document, _savedDocument);

  /// Renames the drawing. Takes effect in the library on the next Save; a
  /// blank name is ignored.
  void renameDrawing(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == title) return;
    title = trimmed;
    notifyListeners();
  }

  /// Gives the drawing as it is now a new identity (Save as). Its content,
  /// layer and item IDs, history, and selection are all kept.
  void adoptIdentity(String documentId) {
    _document = _document.withId(documentId);
    _ledger.record(_document);
    notifyListeners();
  }

  /// Records [saved], under [title], as what storage now holds. The
  /// drawing itself is not touched: work done since the save started,
  /// including a rename, still counts as unsaved.
  void markSaved(GardenDocument saved, {String? libraryId, String? title}) {
    _savedDocument = saved;
    if (libraryId != null) this.libraryId = libraryId;
    _savedTitle = title ?? this.title;
    notifyListeners();
  }

  // ------------------------------------------------------------------- view

  Camera _camera;
  Camera get camera => _camera;
  Size _viewport = Size.zero;
  Size get viewport => _viewport;

  WorkspaceSettings _settings;
  WorkspaceSettings get settings => _settings;

  /// Switches the canvas between the Wireframe drawing and the Render
  /// view. A workspace choice, not part of the drawing's history.
  void setViewMode(ViewMode mode) {
    if (mode == _settings.viewMode) return;
    updateSettings(_settings.copyWith(viewMode: mode));
  }

  void updateSettings(WorkspaceSettings settings) {
    _settings = settings;
    _history.resize(settings.appearance.historyCapacity);
    final limits = settings.appearance.heightLimits;
    if (limits.clamp(_camera.height) != _camera.height) {
      _camera = _camera.atHeight(
        limits.clamp(_camera.height),
        anchor: _viewport.center(Offset.zero),
      );
    }
    notifyListeners();
  }

  /// A drawing opened without a remembered view (e.g. a file imported on
  /// another computer) is framed once the canvas knows its size, so a
  /// drawing far from the origin does not open on an empty screen.
  bool _fitOnFirstView;

  void setViewportSize(Size size) {
    if (size == _viewport) return;
    if (_viewport != Size.zero) _camera = _camera.resized(_viewport, size);
    _viewport = size;
    if (_fitOnFirstView && !size.isEmpty) {
      _fitOnFirstView = false;
      return fitDrawing();
    }
    notifyListeners();
  }

  /// Fires when only the view (pan, zoom) or the tool preview changed.
  ///
  /// These change on nearly every pointer move. Only the canvas and the
  /// status bar's zoom readout show them, so they skip the ordinary
  /// listeners, which rebuild the whole screen with its panels.
  Listenable get viewChanges => _viewChanges;
  final _Signal _viewChanges = _Signal();

  @override
  void dispose() {
    _guideDwell?.cancel();
    _viewChanges.dispose();
    super.dispose();
  }

  void panBy(Offset screenDelta) {
    _camera = _camera.panBy(screenDelta);
    _viewChanges.fire();
  }

  void zoomAt(Offset anchor, int steps) {
    final next = _camera.zoomAt(
      anchor,
      steps,
      limits: _settings.appearance.heightLimits,
    );
    // Wheeling past the lowest or highest camera changes nothing, so draws
    // nothing.
    if (next.height == _camera.height && next.topLeft == _camera.topLeft) {
      return;
    }
    _camera = next;
    _viewChanges.fire();
  }

  /// The starting camera height, within the height limits, with the world
  /// origin at the viewport's top-left.
  void resetView() {
    _camera = Camera(
      height: _settings.appearance.heightLimits.clamp(Camera.startHeight),
    );
    notifyListeners();
  }

  /// Frames every committed point, leaving room for the side panels.
  void fitDrawing({double leftGutter = 0, double rightGutter = 0}) {
    final points = [
      for (final geometry in _document.geometries.values) ...[
        ...geometry.points.values,
        for (final line in geometry.lines.values) ...[
          line.bounds(geometry.points).$1,
          line.bounds(geometry.points).$2,
        ],
        for (final circle in geometry.circles.values)
          for (final corner in [Vec(-1, -1), Vec(1, 1)])
            geometry.points[circle.center]! + corner * circle.radius,
      ],
      for (final image in _document.references) ...image.corners,
    ];
    if (points.isEmpty || _viewport.isEmpty) return resetView();
    var minX = points.first.x, maxX = points.first.x;
    var minY = points.first.y, maxY = points.first.y;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    const margin = 40.0;
    final usableWidth = _viewport.width - leftGutter - rightGutter - 2 * margin;
    final usableHeight = _viewport.height - 2 * margin;
    final width = maxX - minX, height = maxY - minY;
    final limits = _settings.appearance.heightLimits;
    var cameraHeight = limits.lowest;
    if (width > 0) {
      cameraHeight = math.max(
        cameraHeight,
        Camera.heightFor(metres: width, pixels: usableWidth),
      );
    }
    if (height > 0) {
      cameraHeight = math.max(
        cameraHeight,
        Camera.heightFor(metres: height, pixels: usableHeight),
      );
    }
    final camera = Camera(height: limits.clamp(cameraHeight));
    final centre = Vec((minX + maxX) / 2, (minY + maxY) / 2);
    final screenCentre = Vec(
      leftGutter + (_viewport.width - leftGutter - rightGutter) / 2,
      _viewport.height / 2,
    );
    _camera = Camera(
      topLeft: centre - screenCentre / camera.pixelsPerMetreNow,
      height: camera.height,
    );
    notifyListeners();
  }

  // ------------------------------------------------------------ interaction

  String? _selectedLayerId;
  String? get selectedLayerId => _selectedLayerId;
  Layer? get selectedLayer => _document.layers[_selectedLayerId];

  final Set<String> _selection = {};

  /// Selected items in the selected layer's geometry.
  Set<String> get selection => Set.unmodifiable(_selection);

  /// The geometry last hovered, which guides come from.
  final GuideMemory guideMemory = GuideMemory();
  List<ItemRef> get recentGuideItems => guideMemory.recent;

  /// Reports the point, line or circle under the pointer, for guides.
  /// Only the canvas redraws.
  void hoverGuideItem(ItemRef? item) {
    _guideDwell?.cancel();
    if (guideMemory.hover(item)) _viewChanges.fire();
    // A pointer resting still sends no more events, so check again once
    // the dwell has passed.
    if (item != null) {
      _guideDwell = Timer(GuideMemory.dwell, () {
        if (guideMemory.settle()) _viewChanges.fire();
      });
    }
  }

  Timer? _guideDwell;

  /// Whether Properties is showing its content: shown and not minimized.
  bool get propertiesOpen =>
      !_settings.minimizedPanels.contains(PanelId.properties) &&
      !_settings.hiddenPanels.contains(PanelId.properties);

  Tool _tool = Tool.select;
  Tool get tool => _tool;
  ToolFunction _function = ToolFunction.marquee;
  ToolFunction get function => _function;
  final Map<Tool, ToolFunction> _functionMemory = {};

  Preview? _preview;
  Preview? get preview => _preview;

  /// A short explanation of why the last attempt was refused.
  String? _notice;
  String? get notice => _preview?.problem ?? _notice;

  final DraftRegistry drafts = DraftRegistry();

  /// Tells listeners that a Properties draft changed, so Undo and Redo
  /// availability is refreshed.
  void draftsChanged() => notifyListeners();

  /// Values typed into Preferences but not yet applied, or null.
  ///
  /// Kept here so minimizing the panel preserves them and Save can see them.
  Map<String, String>? preferencesDraft;

  bool get preferencesPending => preferencesDraft != null;

  /// True while a confirmation dialog is open, so the focus change it causes
  /// does not apply a Properties draft behind the user's back.
  bool suspendDraftSettlement = false;

  /// Hook that lets the canvas input handler drop any gesture in progress.
  VoidCallback? onCancelOperation;

  /// Preview-only changes redraw the canvas; refusal changes also notify controls.
  void setPreview(Preview? preview) {
    if (preview == _preview) return;
    final previousNotice = notice;
    _preview = preview;
    if (notice != previousNotice) notifyListeners();
    _viewChanges.fire();
  }

  void showNotice(String? message) {
    if (_preview?.problem != null) _preview = null;
    _notice = message;
    notifyListeners();
  }

  void selectTool(Tool tool) {
    if (tool == _tool) return;
    if (!tool.availableIn(_mode)) return showNotice(plantModeNotice);
    _cancelOperation();
    _functionMemory[_tool] = _function;
    _tool = tool;
    _function = _functionMemory[tool] ?? tool.functions.first;
    // Drawing tools work on layers, so Properties goes back to the layer.
    // Feature keeps its selection so a placed feature can be sized at
    // once; Reference keeps its image for the same reason.
    if (tool != Tool.select && tool != Tool.reference) _clearImageSelection();
    if (tool != Tool.select && tool != Tool.feature) _selectedFeatureId = null;
    if (tool == Tool.reference) {
      // Its settings, and the Upload image button, are in Properties.
      _openProperties();
      _selection.clear();
      if (!_document.hasReferenceLayer) {
        commit('Add Reference', documentForEditing.withReferenceLayer());
        return selectReferenceLayer();
      }
    }
    notifyListeners();
  }

  void selectFunction(ToolFunction function) {
    if (function == _function || !_tool.functions.contains(function)) return;
    _cancelOperation();
    _function = function;
    notifyListeners();
  }

  /// Selects a layer as the drawing destination and opens its Properties.
  ///
  /// Choosing the layer that is already selected only reopens Properties.
  void selectLayer(String? layerId) {
    if (layerId != null &&
        layerId == _selectedLayerId &&
        _selectedFeatureId == null &&
        _selectedImageId == null &&
        !_referenceLayerSelected) {
      _openProperties();
      notifyListeners();
      return;
    }
    drafts.settleForLayerSwitch();
    _cancelOperation();
    _selectedLayerId = layerId;
    _selection.clear();
    _clearOverlaySelection();
    if (layerId != null) _openProperties();
    notifyListeners();
  }

  // ----------------------------------------------------------------- panels

  /// Shows or hides a panel (View menu).
  void setPanelVisible(PanelId panel, bool visible) {
    if (!visible) _settleIfHidingProperties(panel);
    final hidden = {..._settings.hiddenPanels};
    visible ? hidden.remove(panel) : hidden.add(panel);
    updateSettings(_settings.copyWith(hiddenPanels: hidden));
  }

  /// Collapses a panel to its heading, or expands it again.
  void setPanelMinimized(PanelId panel, bool minimized) {
    if (minimized) _settleIfHidingProperties(panel);
    final set = {..._settings.minimizedPanels};
    minimized ? set.add(panel) : set.remove(panel);
    updateSettings(_settings.copyWith(minimizedPanels: set));
  }

  /// Folds a dock down to its rail, or opens it.
  void setDockOpen(DockSide side, bool open) {
    if (!open && side == PanelId.properties.side) drafts.settleForLayerSwitch();
    updateSettings(
      _settings.copyWith(docks: _settings.docks.withOpen(side, open)),
    );
  }

  /// Sets a dock's panel width while its edge is dragged. Not part of the
  /// drawing's history; remembered with the workspace.
  void setDockWidth(DockSide side, double width) {
    final next = _settings.docks.withWidth(side, width);
    if (next.widthOf(side) == _settings.docks.widthOf(side)) return;
    updateSettings(_settings.copyWith(docks: next));
  }

  /// Reorders the [visible] panels of a dock; see [DockLayout.moved].
  void movePanel(DockSide side, List<PanelId> visible, int from, int to) {
    updateSettings(
      _settings.copyWith(docks: _settings.docks.moved(side, visible, from, to)),
    );
  }

  /// Hiding Properties counts as closing it: typed values are settled
  /// first, as when switching layers.
  void _settleIfHidingProperties(PanelId panel) {
    if (panel == PanelId.properties) drafts.settleForLayerSwitch();
  }

  /// Expands Properties so a newly selected layer's details show. A folded
  /// dock is left folded; the user folded it on purpose.
  void _openProperties() {
    if (propertiesOpen) return;
    _settings = _settings.copyWith(
      minimizedPanels: {..._settings.minimizedPanels}
        ..remove(PanelId.properties),
      hiddenPanels: {..._settings.hiddenPanels}..remove(PanelId.properties),
    );
  }

  /// Selects [itemId] on [layerId], switching to that layer if needed.
  ///
  /// Used by the Select tool, which reaches every layer. Unlike
  /// [selectLayer] it leaves a gesture in progress alone, so the object can
  /// be dragged straight away. [toggle] adds to or removes from the
  /// selection, but only within the layer already selected.
  void selectObject(String layerId, String itemId, {bool toggle = false}) {
    if (!_document.layers.containsKey(layerId)) return;
    _clearOverlaySelection();
    if (layerId != _selectedLayerId) {
      drafts.settleForLayerSwitch();
      _selectedLayerId = layerId;
      _selection.clear();
      toggle = false;
    }
    _openProperties();
    selectItem(itemId, toggle: toggle);
  }

  /// Selects [itemIds] on [layerId] after a marquee or lasso, switching to
  /// that layer if needed. [add] keeps what was already selected on it.
  void selectItems(String layerId, Set<String> itemIds, {bool add = false}) {
    if (!_document.layers.containsKey(layerId)) return;
    _clearOverlaySelection();
    if (layerId != _selectedLayerId) {
      drafts.settleForLayerSwitch();
      _selectedLayerId = layerId;
      add = false;
    }
    if (!add) _selection.clear();
    _selection.addAll(itemIds);
    _openProperties();
    notifyListeners();
  }

  /// A Select click on empty ground: nothing stays selected, not even the
  /// layer, so the user can always get back to a clean slate.
  void deselectAll() => selectLayer(null);

  /// Replaces or toggles the geometry selection after a click.
  void selectItem(String? itemId, {bool toggle = false}) {
    if (itemId != null || !toggle) _clearOverlaySelection();
    if (itemId == null) {
      if (!toggle) _selection.clear();
    } else if (toggle) {
      if (!_selection.remove(itemId)) _selection.add(itemId);
    } else {
      _selection
        ..clear()
        ..add(itemId);
    }
    notifyListeners();
  }

  /// Handles Escape: ends the current operation, or else clears selection.
  void escape() {
    if (_construction.isActive) {
      _cancelOperation();
    } else if (_selection.isNotEmpty) {
      _selection.clear();
    } else {
      _clearOverlaySelection();
    }
    _preview = null;
    notifyListeners();
  }

  final ConstructionState _construction = ConstructionState();

  String? get lineAnchor => _construction.lineAnchor;
  int? get lineToken => _construction.lineToken;
  Vec get curveHandle => _construction.curveHandle;
  List<ArcPoint> get arcPoints => List.unmodifiable(_construction.arcPoints);
  CircleStart? get circleStart => _construction.circleStart;
  Vec? get polygonStart => _construction.polygonStart;

  void setCurveHandle(Vec offset) {
    _construction.curveHandle = offset;
    notifyListeners();
  }

  void addArcPoint(ArcPoint point) {
    _construction.arcPoints.add(point);
    notifyListeners();
  }

  void setCircleStart(CircleStart? start) {
    _construction.circleStart = start;
    notifyListeners();
  }

  void setPolygonStart(Vec? start) {
    _construction.polygonStart = start;
    notifyListeners();
  }

  int _polygonSides = defaultPolygonSides;
  int get polygonSides => _polygonSides;
  static const defaultPolygonSides = 6;
  static const minPolygonSides = 3;
  static const maxPolygonSides = 24;

  void setPolygonSides(int sides) {
    final clamped = sides.clamp(minPolygonSides, maxPolygonSides);
    if (clamped == _polygonSides) return;
    _polygonSides = clamped;
    _preview = null;
    notifyListeners();
  }

  int startLineOperation() => _construction.startLine();

  void setLineAnchor(String? pointId) {
    _construction.lineAnchor = pointId;
    notifyListeners();
  }

  void _cancelOperation() {
    _construction.reset();
    _referenceOpacityDraft = null;
    _preview = null;
    _notice = null;
    onCancelOperation?.call();
  }

  void cancelOperation() {
    _cancelOperation();
    notifyListeners();
  }

  // ---------------------------------------------------------------- editing

  /// The document with ID counters raised past every number already used,
  /// ready for new points or lines to be added.
  GardenDocument get documentForEditing => _document.withCounterFloor(_ledger);

  /// Builds the result of a geometry change without committing it.
  ///
  /// Only changes the drawing cannot represent are refused, such as a point
  /// joining a third line; the reason is returned instead. Changes that
  /// break a land rule are allowed: the layer is marked invalid instead.
  ///
  /// Locked layers are refused too.
  (GardenDocument?, String?) tryGeometryEdit(
    String layerId,
    void Function(GeometryEditor editor) change,
  ) {
    final locked = geometryLockNotice(layerId);
    if (locked != null) return (null, locked);
    final base = documentForEditing;
    try {
      final geometry = base.geometryOf(layerId).edit(change);
      return (base.withGeometry(geometry), null);
    } on GeometryRuleError catch (error) {
      return (null, error.message);
    }
  }

  /// Applies a change to the drawing and records it for Undo.
  ///
  /// If the change makes a layer invalid, the status bar says which and
  /// why. Edits that are not part of a live Line drawing end that drawing.
  void commit(String label, GardenDocument next, {LineContext? lineContext}) {
    if (identical(next, _document)) return;
    if (!_allowsLayoutOf(next)) return showNotice(plantModeNotice);
    if (lineContext == null) _construction.reset();
    _history.record(
      HistoryEntry(
        label: label,
        before: _document,
        after: next,
        lineContext: lineContext,
      ),
    );
    _notice = _describeNewProblems(next, next.newProblemsSince(_document));
    _setDocument(next);
  }

  static String? _describeNewProblems(
    GardenDocument document,
    Map<String, String> problems,
  ) {
    if (problems.isEmpty) return null;
    final first = problems.entries.first;
    final more = problems.length > 1
        ? ' (and ${problems.length - 1} more)'
        : '';
    return '${document.layers[first.key]!.name} is invalid: ${first.value}$more';
  }

  // ---------------------------------------------------------------- locking

  /// Why [layerId] cannot be edited because of a lock, or null if it can.
  ///
  /// In Plant mode only grow-zone planting and metadata remain editable.
  /// Geometry uses [geometryLockNotice] instead.
  String? lockNotice(String layerId) {
    final by = _document.lockedBy(layerId);
    final name = _document.layers[layerId]?.name ?? 'This layer';
    if (by != null) {
      return by.id == layerId
          ? '$name is locked. Unlock it in Layers to change it'
          : '$name is inside ${by.name}, which is locked';
    }
    if (_mode == EditMode.plant && !isGrowZone(layerId)) {
      return plantModeNotice;
    }
    return null;
  }

  /// Whether [layerId] cannot be changed now: locked, or frozen by Plant
  /// mode. Canvas input skips such layers, so clicks pass through them.
  bool isFrozen(String layerId) => lockNotice(layerId) != null;

  /// Geometry is fixed in Plant, even on a selectable, plantable grow zone.
  String? geometryLockNotice(String layerId) =>
      _mode == EditMode.plant ? plantModeNotice : lockNotice(layerId);

  static const plantModeNotice =
      'Plant mode: geometry is locked. Switch to Build to edit the layout';

  // ------------------------------------------------------------ plant mode

  EditMode _mode = EditMode.build;

  /// Build lays out land; Plant changes only grow zones and plants seeds.
  EditMode get mode => _mode;

  /// Switches between Build and Plant. Plant keeps the selection only on
  /// a grow zone, and swaps a tool it does not offer for Select.
  void setMode(EditMode mode) {
    if (mode == _mode) return;
    drafts.settleForLayerSwitch();
    _cancelOperation();
    _mode = mode;
    _notice = null;
    if (mode == EditMode.plant) {
      if (!_tool.availableIn(mode)) {
        _functionMemory[_tool] = _function;
        _tool = Tool.select;
        _function = _functionMemory[Tool.select] ?? Tool.select.functions.first;
      }
      _clearOverlaySelection();
      if (_selectedLayerId != null && !isGrowZone(_selectedLayerId!)) {
        _selection.clear();
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ visibility

  /// The Reference layer's ID in [WorkspaceSettings.hiddenLayers].
  static const referenceLayerKey = 'reference';

  /// Whether [layerId] is hidden, on its own or with its property. Hidden
  /// layers are not drawn and clicks pass through them. Hiding is a view
  /// choice: it is not an Undo step and does not change the drawing.
  bool isLayerHidden(String layerId) {
    final hidden = _settings.hiddenLayers;
    if (hidden.contains(layerId)) return true;
    final parent = _document.layers[layerId]?.parentId;
    return parent != null && hidden.contains(parent);
  }

  bool get referenceHidden =>
      _settings.hiddenLayers.contains(referenceLayerKey);

  /// Every layer that is hidden right now, including zones of a hidden
  /// property.
  Set<String> get hiddenLayerIds => {
    for (final id in _document.layers.keys)
      if (isLayerHidden(id)) id,
  };

  /// Shows or hides a layer, or the Reference layer by [referenceLayerKey].
  void setLayerHidden(String layerId, bool hidden) {
    final set = {..._settings.hiddenLayers};
    if (!(hidden ? set.add(layerId) : set.remove(layerId))) return;
    _cancelOperation();
    if (hidden && layerId == referenceLayerKey) _clearImageSelection();
    if (hidden &&
        _document.layers.containsKey(layerId) &&
        _document.subtree(layerId).contains(_selectedLayerId)) {
      _selection.clear();
    }
    updateSettings(_settings.copyWith(hiddenLayers: set));
  }

  /// Why the canvas cannot act on [layerId] because it is hidden, or null.
  String? hiddenNotice(String layerId) => isLayerHidden(layerId)
      ? '${_document.layers[layerId]?.name ?? 'This layer'} is hidden. '
            'Show it in Layers to work on it'
      : null;

  /// Whether the canvas skips [layerId]: locked, frozen by Plant mode, or
  /// hidden.
  bool isUnreachable(String layerId) =>
      isFrozen(layerId) || isLayerHidden(layerId);

  /// Whether [layerId] is a grow zone.
  bool isGrowZone(String layerId) =>
      switch (_document.layers[layerId]?.properties) {
        ZoneProperties p => p.isGrow,
        _ => false,
      };

  /// Plants [seed] in grow zone [layerId] as one Undo step; null takes it
  /// out. Used by dropping a seed on the canvas and by Properties.
  void setSeed(String layerId, ZoneSeed? seed) {
    _changeZone(
      layerId,
      seed == null ? 'Remove seed' : 'Plant ${seed.name}',
      (document) => document.withSeed(layerId, seed),
    );
  }

  /// Locks or unlocks a layer, as an undoable step.
  ///
  /// A locked layer, and every zone of a locked property, cannot be drawn
  /// on, moved, renamed, changed, or deleted, and clicks on the canvas
  /// pass through it. It can still be selected in Layers to read its
  /// details.
  void setLayerLocked(String layerId, bool locked) {
    final layer = _document.layers[layerId];
    if (layer == null || layer.locked == locked) return;
    if (_mode == EditMode.plant && !isGrowZone(layerId)) {
      return showNotice(plantModeNotice);
    }
    if (locked) {
      // Values typed into Properties are applied before the layer freezes.
      drafts.settleForLayerSwitch();
      _cancelOperation();
      if (_document.subtree(layerId).contains(_selectedLayerId)) {
        _selection.clear();
      }
    }
    commit(
      '${locked ? 'Lock' : 'Unlock'} ${layer.name}',
      _document.withLayer(layer.copyWith(locked: locked)),
    );
  }

  /// Adds a property, or a zone under the selected property. Layers adds
  /// by [role] (a bed or a planting); without one a zone is plain ground.
  void addLayer(LayerKind kind, {LayerRole? role}) {
    final blocker = addLayerBlocker(kind, role: role);
    if (blocker != null) return showNotice(blocker);
    drafts.settleForLayerSwitch();
    final (next, layerId) = documentForEditing.addLayer(
      kind,
      parentId: kind == LayerKind.property ? null : _homePropertyId,
      newId: newUuid,
      role: role,
    );
    commit('Add ${role?.label ?? kind.label}', next);
    _cancelOperation();
    _selectedLayerId = layerId;
    _selection.clear();
    _clearOverlaySelection();
    _openProperties();
    notifyListeners();
  }

  /// The property the selected layer is listed under (or is).
  String? get _homePropertyId {
    final selected = selectedLayer;
    if (selected == null) return null;
    return selected.kind == LayerKind.property
        ? selected.id
        : selected.parentId;
  }

  /// Why a layer of [kind] cannot be added right now, or null if it can.
  ///
  /// A zone is listed under the selected property (or the property of the
  /// selected zone) and must stay within it, so that property must be
  /// unlocked and complete first.
  String? addLayerBlocker(LayerKind kind, {LayerRole? role}) {
    if (_mode == EditMode.plant) return plantModeNotice;
    if (kind.parentKind == null) return null;
    if (_document.propertyIds.isEmpty) return 'Add a property layer first';
    final label = (role?.label ?? kind.label).toLowerCase();
    final propertyId = _homePropertyId;
    if (propertyId == null) return 'Select a property to add a $label';
    final locked = lockNotice(propertyId);
    if (locked != null) return locked;
    if (!_document.isActive(propertyId)) {
      return 'Complete ${_document.layers[propertyId]!.name} before adding '
          'a $label';
    }
    return null;
  }

  /// Why a reference image cannot be added from Layers > Add layer, or
  /// null if it can. Pictures are traced into land, so a property comes
  /// first.
  String? get addReferenceBlocker {
    if (_mode == EditMode.plant) return plantModeNotice;
    if (_document.propertyIds.isEmpty) return 'Add a property layer first';
    return null;
  }

  /// Why [layerId] cannot be deleted: it, its property, or one of its
  /// zones is locked. Null if it can be.
  String? deleteLayerBlocker(String layerId) {
    for (final id in _document.subtree(layerId)) {
      final locked = geometryLockNotice(id);
      if (locked != null) return locked;
    }
    return null;
  }

  /// Removes a layer, and a property's zones with it, as one undoable
  /// step.
  void deleteLayer(String layerId) {
    if (!_document.layers.containsKey(layerId)) return;
    final blocker = deleteLayerBlocker(layerId);
    if (blocker != null) return showNotice(blocker);
    drafts.discardForLayers(_document.subtree(layerId).toSet());
    final name = _document.layers[layerId]!.name;
    commit('Delete $name', _document.removeLayer(layerId));
  }

  /// Names one shape or circle on a layer; blank restores its automatic
  /// name. One Undo step.
  void renameShape(String layerId, String shapeId, String? label) {
    final clean = label?.trim();
    final (next, problem) = tryGeometryEdit(
      layerId,
      (e) => e.setLabel(shapeId, clean == null || clean.isEmpty ? null : clean),
    );
    if (next == null) return showNotice(problem);
    if (sameContent(next, _document)) return;
    commit('Rename shape', next);
  }

  /// Moves a shape one place up (toward the top of the stack, [up] true)
  /// or down. A shape higher in the stack cuts the ones below it when it
  /// is used with Subtract.
  void moveShape(String layerId, String shapeId, {required bool up}) {
    final stack = _document.geometryOf(layerId).stack;
    final index = stack.indexOf(shapeId);
    final target = index + (up ? 1 : -1);
    if (index < 0 || target < 0 || target >= stack.length) return;
    final (next, problem) = tryGeometryEdit(
      layerId,
      (e) => e.moveInStack(shapeId, target),
    );
    if (next == null) return showNotice(problem);
    commit(up ? 'Move shape up' : 'Move shape down', next);
  }

  void renameLayer(String layerId, String name) {
    final layer = _document.layers[layerId];
    if (layer == null || layer.name == name) return;
    final locked = lockNotice(layerId);
    if (locked != null) return showNotice(locked);
    commit('Rename', _document.withLayer(layer.copyWith(name: name)));
  }

  void updateProperties(String layerId, LayerProperties properties) {
    final layer = _document.layers[layerId];
    if (layer == null) return;
    final locked = lockNotice(layerId);
    if (locked != null) return showNotice(locked);
    commit(
      'Change properties',
      _document.withLayer(layer.copyWith(properties: properties)),
    );
  }

  /// Sets a zone's ground (null for plain dirt) as one Undo step. Used by
  /// both the Ground tool and the Properties panel.
  void setGround(String layerId, GroundType? ground) {
    // Plant mode plants grow zones; turning them into soil is Build work.
    if (_mode == EditMode.plant) return showNotice(plantModeNotice);
    _changeZone(
      layerId,
      ground == null ? 'Fallow ground' : '${ground.label} ground',
      (document) => document.withGround(layerId, ground),
    );
  }

  /// Sets a zone's row width, spacing and direction as one Undo step.
  void setRows(String layerId, RowSpec rows) {
    _changeZone(
      layerId,
      'Change rows',
      (document) => document.withRows(layerId, rows),
    );
  }

  /// Applies a zone change unless the zone is locked; a refusal shows its
  /// reason in the status bar instead.
  void _changeZone(
    String layerId,
    String label,
    GardenDocument Function(GardenDocument) change,
  ) {
    if (!_document.layers.containsKey(layerId)) return;
    final locked = lockNotice(layerId);
    if (locked != null) return showNotice(locked);
    final GardenDocument next;
    try {
      next = change(_document);
    } on StateError catch (error) {
      return showNotice(error.message);
    }
    if (identical(next, _document)) return;
    commit(label, next);
  }

  // --------------------------------------------------------------- features

  /// The raised bed, greenhouse or high tunnel selected, or null. Its
  /// sizes show in Properties.
  String? _selectedFeatureId;

  Feature? get selectedFeature => _document.featureById(_selectedFeatureId);

  /// Whether Properties shows the selected feature.
  bool get showsFeature => selectedFeature != null && _tool != Tool.reference;

  /// Selects one feature and opens its Properties. Land stays the drawing
  /// target but nothing on it is selected, so Delete removes the feature.
  void selectFeature(String featureId) {
    if (_document.featureById(featureId) == null) return;
    if (_mode == EditMode.plant) return showNotice(plantModeNotice);
    drafts.settleForLayerSwitch();
    _clearImageSelection();
    _selectedFeatureId = featureId;
    _selection.clear();
    _openProperties();
    notifyListeners();
  }

  /// Places a new feature of [kind] at its usual size, centred on
  /// [centre], as one Undo step, and selects it.
  void addFeature(FeatureKind kind, Vec centre) {
    if (_mode == EditMode.plant) return showNotice(plantModeNotice);
    final (base, id) = documentForEditing.nextFeatureId();
    commit(
      'Add ${kind.label.toLowerCase()}',
      base.withFeature(Feature.placed(id, kind, centre)),
    );
    selectFeature(id);
  }

  /// Commits a changed feature (matched by ID) as one Undo step. Values
  /// that cannot be used are refused with the reason in the status bar.
  void updateFeature(String label, Feature feature) {
    if (_mode == EditMode.plant) return showNotice(plantModeNotice);
    final current = _document.featureById(feature.id);
    if (current == null || feature == current) return;
    if (feature.problem case final problem?) return showNotice(problem);
    commit(label, _document.withFeature(feature));
  }

  /// Removes a feature. Undo brings it back.
  void removeFeature(String featureId) {
    if (_mode == EditMode.plant) return showNotice(plantModeNotice);
    final feature = _document.featureById(featureId);
    if (feature == null) return;
    commit(
      'Delete ${feature.displayName}',
      _document.withoutFeature(featureId),
    );
  }

  // ------------------------------------------------------------- operations

  /// Why a Boolean cannot run on the selection yet, or null when it can
  /// be tried. Used to enable the Operations buttons.
  String? get booleanBlocker {
    final layerId = _selectedLayerId;
    if (layerId == null || _selection.length < 2) {
      return 'Select two or more shapes on one layer';
    }
    return geometryLockNotice(layerId);
  }

  /// Builds the result of a Boolean on the selected shapes without
  /// committing it. Returns the new document and result shape IDs, or the
  /// reason it was refused.
  ({GardenDocument? document, List<String> resultIds, String? problem})
  tryBoolean(BooleanOperation operation) {
    final blocker = booleanBlocker;
    if (blocker != null) {
      return (document: null, resultIds: const [], problem: blocker);
    }
    var resultIds = const <String>[];
    final items = _selection.toList();
    final (next, problem) = tryGeometryEdit(
      _selectedLayerId!,
      (e) => resultIds = e.booleanOf(items, operation),
    );
    return (document: next, resultIds: resultIds, problem: problem);
  }

  /// Shows what [operation] would do to the selection, while the pointer
  /// is over its button: the result in green, or the top shape in red with
  /// the reason in the status bar. Null clears it.
  void previewBoolean(BooleanOperation? operation) {
    final layerId = _selectedLayerId;
    if (operation == null || layerId == null || _selection.length < 2) {
      return _clearOperationPreview<BooleanPreview>();
    }
    final attempt = tryBoolean(operation);
    final geometry = _document.geometryOf(layerId);
    final top = geometry.stack.lastWhere(
      (id) => _selection.any((item) => geometry.shapeIdFor(item) == id),
      orElse: () => _selection.last,
    );
    final next = attempt.document;
    _preview = BooleanPreview(
      layerId: layerId,
      operandId: top,
      resultIds: attempt.resultIds,
      document: next,
      problem: attempt.problem,
      valid: next != null && next.newProblemsSince(_document).isEmpty,
    );
    _notice = null;
    notifyListeners();
  }

  /// Runs Union or Subtract on the selected shapes as one Undo step and
  /// selects the result. A refusal leaves the drawing unchanged and
  /// explains why in the status bar.
  void runBoolean(BooleanOperation operation) {
    final attempt = tryBoolean(operation);
    final next = attempt.document;
    if (next == null) return showNotice(attempt.problem);
    _preview = null;
    commit(operation == BooleanOperation.union ? 'Union' : 'Subtract', next);
    _selection
      ..clear()
      ..addAll(attempt.resultIds);
    notifyListeners();
  }

  // ------------------------------------------------------------------ align

  /// Why Align cannot run on the selection, or null when it can. Align
  /// takes exactly two items on one layer: the first selected stays put,
  /// the second moves into line with it.
  String? get alignBlocker {
    final layerId = _selectedLayerId;
    if (layerId == null || _selection.length != 2) {
      return 'Select two items: the one to align to, then the one to move';
    }
    return geometryLockNotice(layerId);
  }

  /// Builds the result of aligning the second selected item to the first,
  /// without committing it.
  ({AlignResult? result, String? problem}) tryAlign(AlignEdge edge) {
    final blocker = alignBlocker;
    if (blocker != null) return (result: null, problem: blocker);
    final [anchorId, movingId] = _selection.toList();
    try {
      final result = alignItems(
        documentForEditing,
        _selectedLayerId!,
        anchorId,
        movingId,
        edge,
      );
      return (result: result, problem: null);
    } on GeometryRuleError catch (error) {
      return (result: null, problem: error.message);
    }
  }

  /// Shows where the second item would go while the pointer is over an
  /// Align button, drawn like a drag in progress. Null clears it.
  void previewAlign(AlignEdge? edge) {
    if (edge == null) return _clearOperationPreview<AlignPreview>();
    final attempt = tryAlign(edge);
    final result = attempt.result;
    _preview = AlignPreview(
      document: result?.document ?? _document,
      moved: result?.moved ?? const {},
      valid:
          result != null && result.document.newProblemsSince(_document).isEmpty,
      problem: attempt.problem,
    );
    _notice = null;
    notifyListeners();
  }

  /// Moves the second selected item into line with the first as one Undo
  /// step. A refusal leaves the drawing unchanged and says why.
  void runAlign(AlignEdge edge) {
    final attempt = tryAlign(edge);
    final result = attempt.result;
    if (result == null) return showNotice(attempt.problem);
    _preview = null;
    if (sameContent(result.document, _document)) return notifyListeners();
    commit('Align ${edge.label.toLowerCase()}', result.document);
  }

  /// Leaving an Operations button takes away its preview and notice, and
  /// only those: a preview some other tool has put up since stays.
  void _clearOperationPreview<T extends Preview>() {
    if (_preview is! T) return;
    _preview = null;
    notifyListeners();
  }

  // -------------------------------------------------------- reference layer

  /// The reference image selected (with Select, in Layers, or just
  /// uploaded), or null. It shows its corner handles and its Properties.
  String? _selectedImageId;

  /// Whether the Reference layer row itself is selected in Layers.
  bool _referenceLayerSelected = false;

  ReferenceImage? get selectedImage =>
      _document.referenceById(_selectedImageId);

  /// Whether a reference image is selected.
  bool get referenceSelected => selectedImage != null;

  /// Whether the Reference layer row is the selected row in Layers.
  bool get referenceLayerSelected =>
      _referenceLayerSelected && _document.hasReferenceLayer;

  /// Whether Properties shows the Reference layer rather than a land layer.
  bool get showsReference =>
      referenceSelected || referenceLayerSelected || _tool == Tool.reference;

  /// Selects one reference image and opens its Properties. Shapes and
  /// points stay unselected, so Delete removes only the image.
  void selectReference(String imageId) {
    if (_document.referenceById(imageId) == null) return;
    drafts.settleForLayerSwitch();
    _clearOverlaySelection();
    _selectedImageId = imageId;
    _selection.clear();
    _openProperties();
    notifyListeners();
  }

  /// Selects the Reference layer row, showing the layer's Properties
  /// (where more images are added).
  void selectReferenceLayer() {
    drafts.settleForLayerSwitch();
    _clearOverlaySelection();
    _referenceLayerSelected = true;
    _selection.clear();
    _openProperties();
    notifyListeners();
  }

  /// Features and reference images sit over and under the land rather
  /// than on a layer; selecting land, or one of them, drops the other.
  void _clearOverlaySelection() {
    _selectedFeatureId = null;
    _clearImageSelection();
  }

  void _clearImageSelection() {
    _selectedImageId = null;
    _referenceLayerSelected = false;
    _referenceOpacityDraft = null;
  }

  String? get referenceLineImageId => _construction.referenceImageId;
  Vec? get referenceLineStart => _construction.referenceStart;

  void setReferenceLineStart(String? imageId, Vec? pixel) {
    _construction.referenceImageId = pixel == null ? null : imageId;
    _construction.referenceStart = pixel;
    notifyListeners();
  }

  /// Why the Reference tool cannot draw a line right now, or null.
  String? get referenceBlocker {
    if (referenceHidden) {
      return 'Reference is hidden. Show it in Layers to work on it';
    }
    final images = _document.references;
    if (images.isEmpty) return 'Upload an image in Properties first';
    if (images.every((image) => image.locked)) {
      return 'Every reference image is locked';
    }
    return null;
  }

  /// Why Properties > Upload image cannot add a picture now, or null.
  /// The picture goes into the Reference layer, so that layer or one of
  /// its images must be the selection.
  String? get referenceUploadBlocker {
    if (_mode == EditMode.plant) return plantModeNotice;
    if (!referenceSelected && !referenceLayerSelected) {
      return 'Select a reference layer first';
    }
    return null;
  }

  /// Adds an uploaded picture on top of the Reference layer as one Undo
  /// step, fitted to the middle of the view and uncalibrated, and selects
  /// it.
  void addReferenceImage({
    String? fileName,
    required Uint8List bytes,
    required String mimeType,
    required int pixelWidth,
    required int pixelHeight,
  }) {
    if (_mode == EditMode.plant) return showNotice(plantModeNotice);
    final view = _viewport.isEmpty ? const Size(800, 600) : _viewport;
    final (base, id) = documentForEditing.nextImageId();
    final image = ReferenceImage.fitted(
      id: id,
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      viewCentre: _camera.toWorld(view.center(Offset.zero)),
      viewWidth: _camera.metres(view.width),
      viewHeight: _camera.metres(view.height),
    );
    commit('Add reference image', base.withReferenceImage(image));
    selectReference(id);
  }

  /// Takes one image out of the Reference layer. Undo brings it back.
  void removeReference(String imageId) {
    if (_mode == EditMode.plant) return showNotice(plantModeNotice);
    if (_document.referenceById(imageId) == null) return;
    commit('Remove reference image', _document.withoutReferenceImage(imageId));
  }

  /// Deletes the Reference layer with every image in it. One Undo step.
  void removeReferenceLayer() {
    if (_mode == EditMode.plant) return showNotice(plantModeNotice);
    if (!_document.hasReferenceLayer) return;
    commit('Delete Reference', _document.withoutReferenceLayer());
  }

  /// Locks or unlocks every image in the Reference layer, as one Undo
  /// step.
  void setAllReferencesLocked(bool locked) {
    if (_mode == EditMode.plant) return showNotice(plantModeNotice);
    var next = _document;
    for (final image in _document.references) {
      next = next.withReferenceImage(image.withLocked(locked));
    }
    if (sameContent(next, _document)) return;
    commit(locked ? 'Lock Reference' : 'Unlock Reference', next);
  }

  /// Moves an image up (over more of the others) or down in the layer.
  void moveReference(String imageId, {required bool up}) {
    if (_mode == EditMode.plant) return showNotice(plantModeNotice);
    final next = _document.withReferenceMoved(imageId, up: up);
    if (identical(next, _document)) return;
    commit(up ? 'Move image up' : 'Move image down', next);
  }

  /// Commits a changed reference image (matched by ID) as one Undo step.
  /// Unchanged images add nothing to history.
  void updateReference(String label, ReferenceImage image) {
    if (_mode == EditMode.plant) return showNotice(plantModeNotice);
    final current = _document.referenceById(image.id);
    if (current == null || image == current) return;
    commit(label, _document.withReferenceImage(image));
  }

  /// Sets the real length of image [imageId]'s reference line and scales
  /// that image, and only it, to match. Returns why not, or null.
  String? calibrateReference(String imageId, double metres) {
    if (_mode == EditMode.plant) return plantModeNotice;
    final image = _document.referenceById(imageId);
    if (image == null) return 'Select a reference image first';
    if (!image.hasLine) {
      return 'Draw a reference line on this image with the Reference tool';
    }
    if (image.locked) return 'Unlock the image first';
    if (!metres.isFinite || metres <= 0) return 'Enter a distance above zero';
    updateReference('Calibrate reference image', image.calibratedTo(metres));
    return null;
  }

  double? _referenceOpacityDraft;

  /// The opacity to draw [image] with: the slider's value while it is
  /// being dragged (for the selected image), otherwise the saved one.
  double opacityOf(ReferenceImage image) =>
      image.id == _selectedImageId && _referenceOpacityDraft != null
      ? _referenceOpacityDraft!
      : image.opacity;

  /// Shows [value] live while the opacity slider moves; nothing is saved.
  void previewReferenceOpacity(double value) {
    _referenceOpacityDraft = value;
    notifyListeners();
  }

  /// Saves the selected image's opacity when the slider is let go, as one
  /// Undo step.
  void setReferenceOpacity(double value) {
    _referenceOpacityDraft = null;
    final image = selectedImage;
    if (image == null) return notifyListeners();
    updateReference('Reference opacity', image.withOpacity(value));
    notifyListeners();
  }

  /// Whether Delete has something to remove: selected items on the
  /// layer, or else the selected feature or reference image.
  bool get canDeleteSelection {
    if (_selection.isNotEmpty) {
      return _selectedLayerId != null &&
          geometryLockNotice(_selectedLayerId!) == null;
    }
    return _mode == EditMode.build &&
        (_selectedFeatureId != null || _selectedImageId != null);
  }

  /// Deletes the selected items and whatever depends on them. With a
  /// feature or reference image selected instead, removes that.
  void deleteSelection() {
    if (!canDeleteSelection) {
      if (_selection.isNotEmpty && _selectedLayerId != null) {
        showNotice(geometryLockNotice(_selectedLayerId!));
      } else if (_mode == EditMode.plant &&
          (_selectedFeatureId != null || _selectedImageId != null)) {
        showNotice(plantModeNotice);
      }
      return;
    }
    if (_selectedFeatureId != null && _selection.isEmpty) {
      return removeFeature(_selectedFeatureId!);
    }
    if (_selectedImageId != null && _selection.isEmpty) {
      return removeReference(_selectedImageId!);
    }
    final layerId = _selectedLayerId;
    if (layerId == null || _selection.isEmpty) return;
    final items = _selection.toList();
    final (next, problem) = tryGeometryEdit(layerId, (e) => e.delete(items));
    if (next == null) return showNotice(problem);
    commit(items.length == 1 ? 'Delete' : 'Delete ${items.length} items', next);
  }

  // ---------------------------------------------------------------- history

  bool get canUndo =>
      _history.canUndo &&
      !drafts.hasUnappliedChanges &&
      _allowsLayoutOf(_history.undoEntry!.before);
  bool get canRedo =>
      _history.canRedo &&
      !drafts.hasUnappliedChanges &&
      _allowsLayoutOf(_history.redoEntry!.after);
  String? get undoLabel => _history.undoLabel;
  String? get redoLabel => _history.redoLabel;

  /// Plant edits and history can change details, but not the saved layout.
  bool _allowsLayoutOf(GardenDocument next) {
    if (_mode == EditMode.build) return true;
    if (!mapEquals(_document.geometries, next.geometries) ||
        !listEquals(_document.references, next.references) ||
        !listEquals(_document.features, next.features) ||
        !listEquals(_document.propertyIds, next.propertyIds) ||
        _document.layers.length != next.layers.length) {
      return false;
    }
    for (final layer in _document.layers.values) {
      final other = next.layers[layer.id];
      if (other == null ||
          layer.kind != other.kind ||
          layer.parentId != other.parentId ||
          layer.geometryId != other.geometryId ||
          !listEquals(layer.children, other.children)) {
        return false;
      }
      if (layer.properties case ZoneProperties properties) {
        if (other.properties is! ZoneProperties ||
            properties.ground != (other.properties as ZoneProperties).ground) {
          return false;
        }
      }
    }
    return true;
  }

  void undo() {
    if (!canUndo) {
      if (_construction.hasPendingClicks) cancelOperation();
      return;
    }
    final entry = _history.takeUndo()!;
    _restoreLineContext(entry.lineContext, entry.lineContext?.anchorBefore);
    _setDocument(entry.before);
  }

  void redo() {
    if (!canRedo) {
      if (_construction.hasPendingClicks) cancelOperation();
      return;
    }
    final entry = _history.takeRedo()!;
    _restoreLineContext(entry.lineContext, entry.lineContext?.anchorAfter);
    _setDocument(entry.after);
  }

  /// Resumes the dashed Line preview only within the same live drawing.
  void _restoreLineContext(LineContext? context, String? anchor) {
    _construction.restoreLine(
      context,
      anchor,
      drawingLine:
          _tool == Tool.line &&
          (_function == ToolFunction.draw || _function == ToolFunction.curve),
    );
    _preview = null;
    _notice = null;
    onCancelOperation?.call();
  }

  // --------------------------------------------------------------- internal

  void _setDocument(GardenDocument next) {
    // History made before Save as holds the old identity; keep the new one.
    _document = next.id == _document.id ? next : next.withId(_document.id);
    _ledger.record(next);
    _dropStaleReferences();
    notifyListeners();
  }

  /// Clears selection and references to items that no longer exist.
  void _dropStaleReferences() {
    if (_document.featureById(_selectedFeatureId) == null) {
      _selectedFeatureId = null;
    }
    if (_document.referenceById(_selectedImageId) == null) {
      _selectedImageId = null;
      _referenceOpacityDraft = null;
    }
    if (!_document.hasReferenceLayer) _referenceLayerSelected = false;
    if (_document.referenceById(_construction.referenceImageId) == null) {
      _construction.referenceImageId = null;
      _construction.referenceStart = null;
    }
    if (!_document.layers.containsKey(_selectedLayerId)) {
      _selectedLayerId = null;
      _selection.clear();
    }
    final geometry = _selectedLayerId == null
        ? null
        : _document.geometryOf(_selectedLayerId!);
    _selection.removeWhere((id) => geometry == null || !geometry.contains(id));
    final layerGeometry = geometry;
    if (layerGeometry?.points[_construction.lineAnchor] == null) {
      _construction.lineAnchor = null;
    }
  }
}

/// A bare change signal; see [EditorController.viewChanges].
class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}
