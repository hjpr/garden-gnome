import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/document.dart';
import '../domain/fill_patterns.dart';
import '../domain/geometry.dart';
import '../domain/land_rules.dart';
import '../domain/layer.dart';
import '../domain/reference_image.dart';
import '../domain/region.dart';
import '../domain/vec.dart';
import 'alignment.dart';
import 'camera.dart';
import 'drafts.dart';
import 'guides.dart';
import 'history.dart';
import 'previews.dart';
import 'toasts.dart';
import 'tools.dart';
import 'workspace_settings.dart';

const _uuid = Uuid();

/// The owner recorded on Properties drafts typed for the reference image,
/// which is not a layer.
const referenceDraftOwner = 'reference-image';
String newUuid() => _uuid.v4();

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

  /// Switches to a copy of the drawing with a new identity (Save as).
  ///
  /// Layer and item IDs, history, and selection are kept.
  void replaceDocumentIdentity(GardenDocument copy) {
    _document = copy;
    _ledger.record(copy);
    notifyListeners();
  }

  /// Records [saved] as the content now held in storage.
  void markSaved(GardenDocument saved, {String? libraryId, String? title}) {
    _savedDocument = saved;
    if (libraryId != null) this.libraryId = libraryId;
    if (title != null) this.title = title;
    _savedTitle = this.title;
    notifyListeners();
  }

  // ------------------------------------------------------------------- view

  Camera _camera;
  Camera get camera => _camera;
  Size _viewport = Size.zero;
  Size get viewport => _viewport;

  WorkspaceSettings _settings;
  WorkspaceSettings get settings => _settings;

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
  String? get notice => _notice;

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

  /// Shows tool feedback on the canvas. Only the canvas redraws; see
  /// [viewChanges].
  void setPreview(Preview? preview) {
    if (preview == _preview) return;
    _preview = preview;
    _viewChanges.fire();
  }

  void showNotice(String? message) {
    _notice = message;
    notifyListeners();
  }

  void selectTool(Tool tool) {
    if (tool == _tool) return;
    _cancelOperation();
    _functionMemory[_tool] = _function;
    _tool = tool;
    _function = _functionMemory[tool] ?? tool.functions.first;
    // Drawing tools work on layers, so Properties goes back to the layer.
    if (tool != Tool.select && tool != Tool.reference) {
      _clearReferenceSelection();
    }
    if (tool == Tool.reference) {
      // Its settings, and the Add image button, are in Properties.
      _openProperties();
      _selection.clear();
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
    if (layerId != null && layerId == _selectedLayerId) {
      _openProperties();
      notifyListeners();
      return;
    }
    drafts.settleForLayerSwitch();
    _cancelOperation();
    _selectedLayerId = layerId;
    _selection.clear();
    _clearReferenceSelection();
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
    _clearReferenceSelection();
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
    _clearReferenceSelection();
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

  /// Replaces or toggles the geometry selection after a click.
  void selectItem(String? itemId, {bool toggle = false}) {
    if (itemId != null || !toggle) _clearReferenceSelection();
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
    if (_lineAnchor != null ||
        _lineToken != null ||
        _circleStart != null ||
        _polygonStart != null ||
        _referenceLineStart != null ||
        _arcPoints.isNotEmpty) {
      _cancelOperation();
    } else if (_selection.isNotEmpty) {
      _selection.clear();
    } else if (_selectedImageId != null || _referenceLayerSelected) {
      _clearReferenceSelection();
    }
    _preview = null;
    notifyListeners();
  }

  // ----------------------------------------------------- live Line operation

  int _tokenCounter = 0;
  int? _lineToken;
  String? _lineAnchor;

  /// The point the dashed Line preview starts from, if drawing.
  String? get lineAnchor => _lineAnchor;

  Vec _curveHandle = Vec.zero;

  /// Line → Curve: the handle pulled out at the last point placed, as an
  /// offset from it. The next curve piece leaves that point along it.
  Vec get curveHandle => _curveHandle;

  void setCurveHandle(Vec offset) {
    _curveHandle = offset;
    notifyListeners();
  }

  final List<ArcPoint> _arcPoints = [];

  /// Start and through clicks stay outside the document until Arc completes.
  List<ArcPoint> get arcPoints => List.unmodifiable(_arcPoints);

  void addArcPoint(ArcPoint point) {
    _arcPoints.add(point);
    notifyListeners();
  }

  CircleStart? _circleStart;

  /// The first click of a circle being drawn, if waiting for the second.
  /// It is not part of the drawing until the circle is finished.
  CircleStart? get circleStart => _circleStart;

  void setCircleStart(CircleStart? start) {
    _circleStart = start;
    notifyListeners();
  }

  Vec? _polygonStart;

  /// The first click of a Polygon (its centre, or one corner of a
  /// Rectangle). Like a circle's first click, it is not in the drawing yet.
  Vec? get polygonStart => _polygonStart;

  void setPolygonStart(Vec? start) {
    _polygonStart = start;
    notifyListeners();
  }

  /// Sides for Polygon → Regular. Kept between uses of the tool.
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

  int? get lineToken => _lineToken;

  /// Starts a new Line drawing operation and returns its token.
  int startLineOperation() => _lineToken = ++_tokenCounter;

  void setLineAnchor(String? pointId) {
    _lineAnchor = pointId;
    notifyListeners();
  }

  /// Ends any drawing in progress. Placed points and lines stay.
  void _cancelOperation() {
    _lineToken = null;
    _lineAnchor = null;
    _curveHandle = Vec.zero;
    _circleStart = null;
    _polygonStart = null;
    _referenceLineStart = null;
    _referenceLineImageId = null;
    _referenceOpacityDraft = null;
    _arcPoints.clear();
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
    final locked = lockNotice(layerId);
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
    if (lineContext == null) {
      _lineToken = null;
      _lineAnchor = null;
      _curveHandle = Vec.zero;
      _circleStart = null;
      _polygonStart = null;
      _referenceLineStart = null;
      _referenceLineImageId = null;
      _arcPoints.clear();
    }
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
  String? lockNotice(String layerId) {
    final by = _document.lockedBy(layerId);
    if (by == null) return null;
    final name = _document.layers[layerId]!.name;
    return by.id == layerId
        ? '$name is locked. Unlock it in Layers to change it'
        : '$name is inside ${by.name}, which is locked';
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

  /// Adds a property, or a zone under the selected property.
  void addLayer(LayerKind kind) {
    final blocker = addLayerBlocker(kind);
    if (blocker != null) return showNotice(blocker);
    drafts.settleForLayerSwitch();
    final (next, layerId) = documentForEditing.addLayer(
      kind,
      parentId: kind == LayerKind.property ? null : _homePropertyId,
      newId: newUuid,
    );
    commit('Add ${kind.label}', next);
    _cancelOperation();
    _selectedLayerId = layerId;
    _selection.clear();
    _clearReferenceSelection();
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
  String? addLayerBlocker(LayerKind kind) {
    if (kind.parentKind == null) return null;
    final label = kind.label.toLowerCase();
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

  /// Why [layerId] cannot be deleted: it, its property, or one of its
  /// zones is locked. Null if it can be.
  String? deleteLayerBlocker(String layerId) {
    for (final id in _document.subtree(layerId)) {
      final locked = lockNotice(id);
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

  /// Sets a layer's decorative pattern (null for none) as one Undo step.
  /// Used by both the Pattern tool and the Properties panel.
  void setPattern(String layerId, FillPattern? pattern) {
    if (!_document.layers.containsKey(layerId)) return;
    final locked = lockNotice(layerId);
    if (locked != null) return showNotice(locked);
    final GardenDocument next;
    try {
      next = _document.withPattern(layerId, pattern);
    } on StateError catch (error) {
      return showNotice(error.message);
    }
    if (identical(next, _document)) return;
    commit(pattern == null ? 'Remove pattern' : 'Pattern', next);
  }

  // ------------------------------------------------------------- operations

  /// Why a Boolean cannot run on the selection yet, or null when it can
  /// be tried. Used to enable the Operations buttons.
  String? get booleanBlocker {
    final layerId = _selectedLayerId;
    if (layerId == null || _selection.length < 2) {
      return 'Select two or more shapes on one layer';
    }
    return lockNotice(layerId);
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
      if (_preview is BooleanPreview) {
        _preview = null;
        _notice = null;
        notifyListeners();
      }
      return;
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
    _notice = attempt.problem;
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
    return lockNotice(layerId);
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

  bool _alignPreviewing = false;

  /// Shows where the second item would go while the pointer is over an
  /// Align button, drawn like a drag in progress. Null clears it.
  void previewAlign(AlignEdge? edge) {
    if (edge == null) {
      if (_alignPreviewing) {
        _alignPreviewing = false;
        _preview = null;
        _notice = null;
        notifyListeners();
      }
      return;
    }
    final attempt = tryAlign(edge);
    final result = attempt.result;
    _alignPreviewing = true;
    _preview = result == null
        ? null
        : MovePreview(
            document: result.document,
            moved: result.moved,
            valid: result.document.newProblemsSince(_document).isEmpty,
          );
    _notice = attempt.problem;
    notifyListeners();
  }

  /// Moves the second selected item into line with the first as one Undo
  /// step. A refusal leaves the drawing unchanged and says why.
  void runAlign(AlignEdge edge) {
    final attempt = tryAlign(edge);
    final result = attempt.result;
    if (result == null) return showNotice(attempt.problem);
    _alignPreviewing = false;
    _preview = null;
    if (sameContent(result.document, _document)) return notifyListeners();
    commit('Align ${edge.label.toLowerCase()}', result.document);
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
      _referenceLayerSelected && _document.references.isNotEmpty;

  /// Whether Properties shows the Reference layer rather than a land layer.
  bool get showsReference =>
      referenceSelected || referenceLayerSelected || _tool == Tool.reference;

  /// Selects one reference image and opens its Properties. Shapes and
  /// points stay unselected, so Delete removes only the image.
  void selectReference(String imageId) {
    if (_document.referenceById(imageId) == null) return;
    drafts.settleForLayerSwitch();
    _selectedImageId = imageId;
    _referenceLayerSelected = false;
    _referenceOpacityDraft = null;
    _selection.clear();
    _openProperties();
    notifyListeners();
  }

  /// Selects the Reference layer row, showing the layer's Properties
  /// (where more images are added).
  void selectReferenceLayer() {
    drafts.settleForLayerSwitch();
    _selectedImageId = null;
    _referenceLayerSelected = true;
    _selection.clear();
    _openProperties();
    notifyListeners();
  }

  void _clearReferenceSelection() {
    _selectedImageId = null;
    _referenceLayerSelected = false;
    _referenceOpacityDraft = null;
  }

  /// The image a reference line is being drawn on, and its first end in
  /// that image's pixels. Neither is in the drawing until the second click.
  String? _referenceLineImageId;
  Vec? _referenceLineStart;

  String? get referenceLineImageId => _referenceLineImageId;
  Vec? get referenceLineStart => _referenceLineStart;

  void setReferenceLineStart(String? imageId, Vec? pixel) {
    _referenceLineImageId = pixel == null ? null : imageId;
    _referenceLineStart = pixel;
    notifyListeners();
  }

  /// Why the Reference tool cannot draw a line right now, or null.
  String? get referenceBlocker {
    final images = _document.references;
    if (images.isEmpty) return 'Add a reference image in Properties first';
    if (images.every((image) => image.locked)) {
      return 'Every reference image is locked';
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
    if (_document.referenceById(imageId) == null) return;
    commit('Remove reference image', _document.withoutReferenceImage(imageId));
  }

  /// Takes every image out, so the Reference layer disappears. One Undo
  /// step.
  void removeReferenceLayer() {
    if (_document.references.isEmpty) return;
    var next = _document;
    for (final image in _document.references) {
      next = next.withoutReferenceImage(image.id);
    }
    commit('Delete Reference', next);
  }

  /// Locks or unlocks every image in the Reference layer, as one Undo
  /// step.
  void setAllReferencesLocked(bool locked) {
    var next = _document;
    for (final image in _document.references) {
      next = next.withReferenceImage(image.withLocked(locked));
    }
    if (sameContent(next, _document)) return;
    commit(locked ? 'Lock Reference' : 'Unlock Reference', next);
  }

  /// Moves an image up (over more of the others) or down in the layer.
  void moveReference(String imageId, {required bool up}) {
    final next = _document.withReferenceMoved(imageId, up: up);
    if (identical(next, _document)) return;
    commit(up ? 'Move image up' : 'Move image down', next);
  }

  /// Commits a changed reference image (matched by ID) as one Undo step.
  /// Unchanged images add nothing to history.
  void updateReference(String label, ReferenceImage image) {
    final current = _document.referenceById(image.id);
    if (current == null || image == current) return;
    commit(label, _document.withReferenceImage(image));
  }

  /// Sets the real length of image [imageId]'s reference line and scales
  /// that image, and only it, to match. Returns why not, or null.
  String? calibrateReference(String imageId, double metres) {
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

  /// Deletes the selected items and whatever depends on them. With the
  /// reference image selected instead, removes the image.
  void deleteSelection() {
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

  bool get canUndo => _history.canUndo && !drafts.hasUnappliedChanges;
  bool get canRedo => _history.canRedo && !drafts.hasUnappliedChanges;
  String? get undoLabel => _history.undoLabel;
  String? get redoLabel => _history.redoLabel;

  /// Whether a multi-click tool is waiting for its next click. Undo and
  /// Redo drop those clicks when there is no history step to take.
  bool get _hasPendingClicks =>
      _arcPoints.isNotEmpty ||
      _circleStart != null ||
      _polygonStart != null ||
      _referenceLineStart != null;

  void undo() {
    if (!canUndo) {
      if (_hasPendingClicks) cancelOperation();
      return;
    }
    final entry = _history.takeUndo()!;
    _restoreLineContext(entry.lineContext, entry.lineContext?.anchorBefore);
    _setDocument(entry.before);
  }

  void redo() {
    if (!canRedo) {
      if (_hasPendingClicks) cancelOperation();
      return;
    }
    final entry = _history.takeRedo()!;
    _restoreLineContext(entry.lineContext, entry.lineContext?.anchorAfter);
    _setDocument(entry.after);
  }

  /// Resumes the dashed Line preview only within the same live drawing.
  void _restoreLineContext(LineContext? context, String? anchor) {
    final live =
        context != null &&
        context.operation == _lineToken &&
        _tool == Tool.line &&
        (_function == ToolFunction.draw || _function == ToolFunction.curve);
    _lineAnchor = live ? anchor : null;
    // The pulled-out handle is not kept in history; the piece after an
    // Undo starts straight from its point.
    _curveHandle = Vec.zero;
    if (!live) _lineToken = null;
    _circleStart = null;
    _polygonStart = null;
    _referenceLineStart = null;
    _referenceLineImageId = null;
    _arcPoints.clear();
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
    if (_document.referenceById(_selectedImageId) == null) {
      _selectedImageId = null;
      _referenceOpacityDraft = null;
    }
    if (_document.references.isEmpty) _referenceLayerSelected = false;
    if (_document.referenceById(_referenceLineImageId) == null) {
      _referenceLineImageId = null;
      _referenceLineStart = null;
      _referenceLineImageId = null;
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
    if (_lineAnchor != null && layerGeometry?.points[_lineAnchor] == null) {
      _lineAnchor = null;
    }
  }
}

/// Whether two documents hold the same drawing, ignoring ID counters.
bool sameContent(GardenDocument a, GardenDocument b) {
  if (identical(a, b)) return true;
  if (a.id != b.id || !listEquals(a.propertyIds, b.propertyIds)) {
    return false;
  }
  if (!listEquals(a.references, b.references)) return false;
  if (a.layers.length != b.layers.length) return false;
  for (final entry in a.layers.entries) {
    if (!identical(entry.value, b.layers[entry.key])) return false;
  }
  if (a.geometries.length != b.geometries.length) return false;
  for (final entry in a.geometries.entries) {
    final other = b.geometries[entry.key];
    if (other == null) return false;
    final mine = entry.value;
    if (identical(mine, other)) continue;
    if (!_sameCircles(mine.circles, other.circles)) return false;
    if (!identical(mine.points, other.points) ||
        !identical(mine.lines, other.lines) ||
        !identical(mine.shapes, other.shapes) ||
        !listEquals(mine.stack, other.stack)) {
      if (!mapEquals(mine.points, other.points) ||
          !_sameLines(mine.lines, other.lines) ||
          !listEquals(mine.stack, other.stack) ||
          !_sameShapes(mine.shapes, other.shapes)) {
        return false;
      }
    }
  }
  return true;
}

bool _sameLines(Map<String, LineSegment> a, Map<String, LineSegment> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null ||
        other.start != entry.value.start ||
        other.end != entry.value.end ||
        other.bulge != entry.value.bulge ||
        other.startHandle != entry.value.startHandle ||
        other.endHandle != entry.value.endHandle) {
      return false;
    }
  }
  return true;
}

bool _sameCircles(Map<String, Circle> a, Map<String, Circle> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null ||
        other.center != entry.value.center ||
        other.radius != entry.value.radius ||
        other.label != entry.value.label) {
      return false;
    }
  }
  return true;
}

bool _sameShapes(Map<String, ClosedShape> a, Map<String, ClosedShape> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    final mine = entry.value;
    if (other == null ||
        other.label != mine.label ||
        other.rings.length != mine.rings.length) {
      return false;
    }
    for (var ring = 0; ring < mine.rings.length; ring++) {
      final a = mine.rings[ring], b = other.rings[ring];
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i].segmentId != b[i].segmentId ||
            a[i].reversed != b[i].reversed) {
          return false;
        }
      }
    }
  }
  return true;
}

/// A bare change signal; see [EditorController.viewChanges].
class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// A temporary Arc click and the open endpoint it may reuse on completion.
class ArcPoint {
  const ArcPoint(this.position, {this.pointId});

  final Vec position;
  final String? pointId;
}

/// The first circle click; only a centre circle reuses [pointId].
class CircleStart {
  const CircleStart(this.position, {this.pointId});

  final Vec position;
  final String? pointId;
}
