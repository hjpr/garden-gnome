import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/document_session.dart';
import '../application/editor_controller.dart';
import '../application/toasts.dart';
import '../application/tool_prompts.dart';
import '../application/tools.dart';
import '../application/workspace_settings.dart';
import '../platform/leave_guard.dart';
import '../platform/persistent_storage.dart';
import 'canvas/drawing_canvas.dart';
import 'dialogs.dart';
import 'panels/layers_panel.dart';
import 'panels/operations_panel.dart';
import 'panels/preferences_panel.dart';
import 'panels/properties_panel.dart';
import 'panels/settings_panel.dart';
import 'panels/tools_panel.dart';
import 'theme.dart';
import 'widgets/dock.dart';
import 'widgets/drawing_title.dart';
import 'widgets/panel.dart';
import 'widgets/selection_readout.dart';
import 'widgets/text_focus.dart';
import 'widgets/toaster.dart';

/// Smallest window the editor supports, in logical pixels.
const Size minimumEditorSize = Size(800, 600);

/// The Build screen: a header with menus, the drawing canvas between two
/// folding docks of panels, and a status bar.
class BuildScreen extends StatefulWidget {
  const BuildScreen({super.key, required this.session});

  final DocumentSession session;

  @override
  State<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends State<BuildScreen> {
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'canvas');
  late final AppLifecycleListener _lifecycle;

  DocumentSession get _session => widget.session;
  EditorController get _editor => _session.editor;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
    _editor.addListener(_onEditorChanged);
    _lifecycle = AppLifecycleListener(
      // Switching away mid-drawing drops the half-made shape, as Esc does.
      onInactive: () => _editor.cancelOperation(),
      // Keep the view and settings if the tab is closed or reloaded.
      onHide: () => unawaited(_session.rememberWorkspace()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _session.removeListener(_onSessionChanged);
    _editor.removeListener(_onEditorChanged);
    _canvasFocus.dispose();
    super.dispose();
  }

  EditorController? _listened;

  void _onSessionChanged() {
    _listened?.removeListener(_onEditorChanged);
    _editor.addListener(_onEditorChanged);
    _listened = _editor;
    _onEditorChanged();
  }

  void _onEditorChanged() {
    _listened ??= _editor;
    setLeaveWarning(_session.hasUnsavedWork);
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------- commands

  void _toast(String message, {bool error = false}) => _session.toasts.show(
    message,
    kind: error ? ToastKind.error : ToastKind.success,
  );

  /// Reports a command's result and returns whether it succeeded.
  bool _report(CommandResult result) {
    switch (result) {
      case Succeeded(:final message):
        if (message != null) _toast(message);
        return true;
      case NeedsAttention(:final message):
        _toast(message, error: true);
        return false;
      case Failed(:final message):
        _toast(message, error: true);
        return false;
    }
  }

  Future<bool> _save() async {
    requestPersistentStorage();
    if (_editor.libraryId == null) return _saveAs();
    return _report(await _session.save());
  }

  Future<bool> _saveAs() async {
    requestPersistentStorage();
    final name = await askForName(context, _editor.title);
    if (name == null) return false;
    return _report(await _session.saveAs(name));
  }

  /// Offers to save unsaved work. Returns false when the user cancels.
  Future<bool> _readyToLeave() async {
    if (!_session.hasUnsavedWork) return true;
    switch (await askToSave(context, _editor.title)) {
      case LeaveChoice.save:
        return _save();
      case LeaveChoice.discard:
        return true;
      case LeaveChoice.cancel:
        return false;
    }
  }

  Future<void> _new() async {
    if (await _readyToLeave()) await _session.newDrawing();
  }

  /// Closes the drawing after offering to save it. The editor always has
  /// a drawing open, so an empty untitled one takes its place.
  Future<void> _close() async {
    if (!await _readyToLeave()) return;
    await _session.newDrawing();
    _toast('Drawing closed');
  }

  Future<void> _open() async {
    // Choose first, so cancelling leaves the current drawing untouched.
    final choice = await chooseDrawing(context, _session.library);
    if (choice == null || !mounted) return;
    switch (choice) {
      case OpenSaved(:final entry):
        if (!await _readyToLeave()) return;
        _report(await _session.open(entry));
      case OpenFromFile():
        await _import();
    }
  }

  Future<void> _import() async {
    const group = XTypeGroup(label: 'Garden Gnome', extensions: ['ggnome']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted || !await _readyToLeave()) return;
    _report(await _session.import(bytes, file.name));
  }

  /// Opens Preferences. Values typed there are held until Apply, and
  /// dropped when the dialog closes.
  Future<void> _preferences() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preferences'),
        content: SizedBox(
          width: 600,
          height: 360,
          child: PreferencesBody(editor: _editor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    _editor.preferencesDraft = null;
    _editor.draftsChanged();
  }

  Future<void> _export() async {
    final name = '${_editor.title.replaceAll(RegExp(r'[^\w\- ]'), '_')}.ggnome';
    try {
      await XFile.fromData(
        _session.export(),
        name: name,
        mimeType: 'application/zip',
      ).saveTo(name);
      _toast('Exported $name');
    } catch (_) {
      _toast('Export failed', error: true);
    }
  }

  // ------------------------------------------------------------- keyboard

  bool get _textHasFocus => textFieldHasFocus();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final key = event.logicalKey;

    if (ctrl) {
      final shift = keys.isShiftPressed;
      void Function()? action = switch (key) {
        LogicalKeyboardKey.keyS when shift => () => unawaited(_saveAs()),
        LogicalKeyboardKey.keyS => () => unawaited(_save()),
        LogicalKeyboardKey.keyO => () => unawaited(_open()),
        LogicalKeyboardKey.keyN => () => unawaited(_new()),
        _ => null,
      };
      if (!_textHasFocus) {
        action ??= switch (key) {
          LogicalKeyboardKey.keyZ when shift => _editor.redo,
          LogicalKeyboardKey.keyZ => _editor.undo,
          LogicalKeyboardKey.keyY => _editor.redo,
          _ => null,
        };
      }
      if (action == null) return KeyEventResult.ignored;
      action();
      return KeyEventResult.handled;
    }

    if (_textHasFocus) return KeyEventResult.ignored;
    switch (key) {
      case LogicalKeyboardKey.keyV:
        _editor.selectTool(Tool.select);
      case LogicalKeyboardKey.keyP:
        _editor.selectTool(Tool.point);
      case LogicalKeyboardKey.keyL:
        _editor.selectTool(Tool.line);
      case LogicalKeyboardKey.keyA:
        _editor.selectTool(Tool.arc);
      case LogicalKeyboardKey.keyC:
        _editor.selectTool(Tool.circle);
      case LogicalKeyboardKey.keyG:
        _editor.selectTool(Tool.polygon);
      case LogicalKeyboardKey.keyF:
        _editor.selectTool(Tool.pattern);
      case LogicalKeyboardKey.keyR:
        _editor.selectTool(Tool.reference);
      case LogicalKeyboardKey.escape:
        _editor.escape();
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        _editor.cancelOperation();
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
        _editor.deleteSelection();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------- panels

  Widget _panel(PanelId id, int index) {
    final editor = _editor;
    final expanded = !editor.settings.minimizedPanels.contains(id);
    void setExpanded(bool open) => editor.setPanelMinimized(id, !open);
    return switch (id) {
      PanelId.tools => DockPanel(
        index: index,
        title: id.label,
        expanded: expanded,
        onExpandedChanged: setExpanded,
        child: ToolsBody(editor: editor),
      ),
      PanelId.operations => DockPanel(
        index: index,
        title: id.label,
        expanded: expanded,
        onExpandedChanged: setExpanded,
        child: OperationsBody(editor: editor),
      ),
      PanelId.settings => DockPanel(
        index: index,
        title: id.label,
        expanded: expanded,
        onExpandedChanged: setExpanded,
        child: SettingsBody(editor: editor),
      ),
      PanelId.properties => DockPanel(
        index: index,
        title: id.label,
        subtitle: editor.showsReference
            ? 'Reference'
            : editor.selectedLayer?.kind.label,
        expanded: expanded,
        onExpandedChanged: setExpanded,
        child: PropertiesBody(editor: editor),
      ),
      PanelId.layers => DockPanel(
        index: index,
        title: id.label,
        expanded: expanded,
        onExpandedChanged: setExpanded,
        footer: LayerActions(editor: editor),
        child: LayersBody(editor: editor),
      ),
    };
  }

  // ---------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tooSmall =
              constraints.maxWidth < minimumEditorSize.width ||
              constraints.maxHeight < minimumEditorSize.height;
          return Scaffold(
            body: Stack(
              children: [
                Column(
                  children: [
                    _Header(
                      title: _editor.title,
                      dirty: _session.hasUnsavedWork,
                      editor: _editor,
                      onNew: _new,
                      onOpen: _open,
                      onSave: _save,
                      onSaveAs: _saveAs,
                      onExport: _export,
                      onClose: _close,
                      onPreferences: _preferences,
                    ),
                    Expanded(
                      child: tooSmall ? const _TooSmallNotice() : _workspace(),
                    ),
                    _StatusBar(editor: _editor),
                  ],
                ),
                Positioned.fill(
                  child: Toaster(
                    toasts: _session.toasts,
                    position: _editor.settings.appearance.toastPosition,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _workspace() {
    final scale = _editor.settings.menuScale.factor;
    Widget dock(DockSide side) => MediaQuery(
      // Menu size scales the docks' text and width; the canvas is unchanged.
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: Dock(
        side: side,
        editor: _editor,
        // Widths are stored at Medium size, so menu size still scales them.
        width: _editor.settings.docks.widthOf(side) * scale,
        buildPanel: _panel,
        onResize: (dx) => _editor.setDockWidth(
          side,
          _editor.settings.docks.widthOf(side) + dx / scale,
        ),
      ),
    );

    // Keyed by the editor so opening another drawing rebuilds every panel
    // and the canvas with fresh state.
    return Row(
      key: ObjectKey(_editor),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        dock(DockSide.left),
        Expanded(
          child: Focus(
            focusNode: _canvasFocus,
            child: Listener(
              onPointerDown: (_) => _canvasFocus.requestFocus(),
              // Its own layer: redrawing the canvas leaves the panels'
              // pixels alone, and panel hovers leave the canvas alone.
              child: ClipRect(
                child: RepaintBoundary(child: DrawingCanvas(editor: _editor)),
              ),
            ),
          ),
        ),
        dock(DockSide.right),
      ],
    );
  }
}

// -------------------------------------------------------------------- header

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.dirty,
    required this.editor,
    required this.onNew,
    required this.onOpen,
    required this.onSave,
    required this.onSaveAs,
    required this.onExport,
    required this.onClose,
    required this.onPreferences,
  });

  final String title;
  final bool dirty;
  final EditorController editor;
  final VoidCallback onNew, onOpen, onSave, onSaveAs, onExport, onClose;
  final VoidCallback onPreferences;

  @override
  Widget build(BuildContext context) {
    MenuItemButton item(
      String label,
      VoidCallback? onPressed, {
      String? shortcut,
      IconData? icon,
    }) => MenuItemButton(
      onPressed: onPressed,
      leadingIcon: SizedBox(
        width: 18,
        child: icon == null ? null : Icon(icon, size: 16, color: Palette.muted),
      ),
      trailingIcon: shortcut == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                shortcut,
                style: const TextStyle(fontSize: 12, color: Palette.faint),
              ),
            ),
      child: Text(label),
    );

    final docks = editor.settings.docks;
    return Container(
      height: Metrics.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Palette.paper,
        border: Border(bottom: BorderSide(color: Palette.panelBorder)),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.eco, size: 20, color: Palette.accent),
          ),
          MenuBar(
            style: const MenuStyle(
              backgroundColor: WidgetStatePropertyAll(Colors.transparent),
              elevation: WidgetStatePropertyAll(0),
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
            ),
            children: [
              SubmenuButton(
                menuChildren: [
                  item(
                    'New',
                    onNew,
                    shortcut: 'Ctrl+N',
                    icon: Icons.note_add_outlined,
                  ),
                  item(
                    'Open…',
                    onOpen,
                    shortcut: 'Ctrl+O',
                    icon: Icons.folder_open_outlined,
                  ),
                  const Divider(),
                  item(
                    'Save',
                    onSave,
                    shortcut: 'Ctrl+S',
                    icon: Icons.save_outlined,
                  ),
                  item('Save as…', onSaveAs, shortcut: 'Ctrl+Shift+S'),
                  const Divider(),
                  item(
                    'Export .ggnome file',
                    onExport,
                    icon: Icons.download_outlined,
                  ),
                  const Divider(),
                  item('Close drawing', onClose, icon: Icons.close),
                ],
                child: const Text('File'),
              ),
              SubmenuButton(
                menuChildren: [
                  item(
                    editor.undoLabel == null
                        ? 'Undo'
                        : 'Undo ${editor.undoLabel}',
                    editor.canUndo ? editor.undo : null,
                    shortcut: 'Ctrl+Z',
                    icon: Icons.undo,
                  ),
                  item(
                    editor.redoLabel == null
                        ? 'Redo'
                        : 'Redo ${editor.redoLabel}',
                    editor.canRedo ? editor.redo : null,
                    shortcut: 'Ctrl+Shift+Z',
                    icon: Icons.redo,
                  ),
                  const Divider(),
                  item(
                    'Delete',
                    editor.selection.isEmpty && !editor.referenceSelected
                        ? null
                        : editor.deleteSelection,
                    shortcut: 'Del',
                    icon: Icons.delete_outline,
                  ),
                  const Divider(),
                  item(
                    'Preferences…',
                    onPreferences,
                    icon: Icons.settings_outlined,
                  ),
                ],
                child: const Text('Edit'),
              ),
              SubmenuButton(
                menuChildren: [
                  for (final side in DockSide.values)
                    CheckboxMenuButton(
                      value: docks.isOpen(side),
                      onChanged: (v) => editor.setDockOpen(side, v ?? true),
                      child: Text(
                        side == DockSide.left ? 'Left panels' : 'Right panels',
                      ),
                    ),
                  const Divider(),
                  for (final id in PanelId.values)
                    CheckboxMenuButton(
                      value: !editor.settings.hiddenPanels.contains(id),
                      onChanged: (v) => editor.setPanelVisible(id, v ?? true),
                      child: Text(id.label),
                    ),
                  const Divider(),
                  item(
                    'Fit drawing',
                    editor.fitDrawing,
                    icon: Icons.fit_screen_outlined,
                  ),
                  item(
                    'Reset view',
                    editor.resetView,
                    icon: Icons.center_focus_strong_outlined,
                  ),
                ],
                child: const Text('View'),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: DrawingTitle(
                title: title,
                dirty: dirty,
                onRename: editor.renameDrawing,
              ),
            ),
          ),
          IconAction(
            iconData: Icons.undo,
            label: editor.undoLabel == null
                ? 'Undo'
                : 'Undo ${editor.undoLabel}',
            tooltip: editor.undoLabel == null
                ? 'Undo (Ctrl+Z)'
                : 'Undo ${editor.undoLabel} (Ctrl+Z)',
            size: 30,
            onPressed: editor.canUndo ? editor.undo : null,
          ),
          IconAction(
            iconData: Icons.redo,
            label: editor.redoLabel == null
                ? 'Redo'
                : 'Redo ${editor.redoLabel}',
            tooltip: editor.redoLabel == null
                ? 'Redo (Ctrl+Shift+Z)'
                : 'Redo ${editor.redoLabel} (Ctrl+Shift+Z)',
            size: 30,
            onPressed: editor.canRedo ? editor.redo : null,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- status bar

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final layer = editor.selectedLayer;
    final path = <String>[];
    for (var l = layer; l != null; l = editor.document.parentOf(l.id)) {
      path.insert(0, l.name);
    }
    final count = editor.selection.length;
    final notice = editor.notice;
    const small = TextStyle(fontSize: 12, color: Palette.muted);
    Widget divider() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(height: 14, child: VerticalDivider(width: 1)),
    );
    final centre = editor.viewport.center(Offset.zero);
    return Container(
      height: Metrics.statusHeight,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: const BoxDecoration(
        color: Palette.paper,
        border: Border(top: BorderSide(color: Palette.panelBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  // What is selected: the selection box's size.
                  SelectionReadout(editor: editor),
                  const SizedBox(width: 12),
                  if (notice != null)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.error_outline,
                        size: 14,
                        color: Palette.invalid,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      notice ?? toolPrompt(editor),
                      overflow: TextOverflow.ellipsis,
                      style: notice == null
                          ? small
                          : const TextStyle(
                              fontSize: 12,
                              color: Palette.invalid,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (path.isNotEmpty) ...[
            Text(path.join(' › '), style: small),
            if (count > 0) Text('  ·  $count selected', style: small),
            divider(),
          ],
          // Zoom changes arrive on viewChanges, which does not rebuild the
          // screen, so the readouts listen for it themselves.
          ListenableBuilder(
            listenable: editor.viewChanges,
            builder: (context, _) => _ScaleReadout(editor: editor),
          ),
          divider(),
          IconAction(
            iconData: Icons.remove,
            label: 'Zoom out',
            size: 22,
            onPressed: () => editor.zoomAt(centre, -1),
          ),
          Tooltip(
            message: 'Camera height. Click to fit drawing',
            child: InkWell(
              onTap: editor.fitDrawing,
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 72,
                child: ListenableBuilder(
                  listenable: editor.viewChanges,
                  builder: (context, _) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.photo_camera_outlined,
                        size: 14,
                        color: Palette.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _cameraHeight(editor),
                        style: small.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconAction(
            iconData: Icons.add,
            label: 'Zoom in',
            size: 22,
            onPressed: () => editor.zoomAt(centre, 1),
          ),
        ],
      ),
    );
  }
}

/// The camera's height above the ground in the user's units, such as
/// "100 ft" or "7.4 ft".
String _cameraHeight(EditorController editor) {
  final units = editor.settings.units;
  final value = units.fromMetres(editor.camera.height);
  final text = value
      .toStringAsFixed(value < 9.95 ? 1 : 0)
      .replaceFirst(RegExp(r'\.0$'), '');
  return '$text ${units.symbol}';
}

/// A bar one grid cell wide, labelled with the length it represents.
class _ScaleReadout extends StatelessWidget {
  const _ScaleReadout({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final cell = editor.camera.gridCellMetres;
    final width = cell * editor.camera.pixelsPerMetreNow;
    return Tooltip(
      message:
          'One grid square is ${editor.settings.units.format(cell)} across',
      child: Row(
        children: [
          Container(
            width: width,
            height: 6,
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: Palette.muted),
                right: BorderSide(color: Palette.muted),
                bottom: BorderSide(color: Palette.muted),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            editor.settings.units.format(cell),
            style: const TextStyle(fontSize: 12, color: Palette.muted),
          ),
        ],
      ),
    );
  }
}

class _TooSmallNotice extends StatelessWidget {
  const _TooSmallNotice();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Make the window at least 800 × 600 to edit the drawing.\n'
        'File → Save still works.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Palette.muted),
      ),
    ),
  );
}
