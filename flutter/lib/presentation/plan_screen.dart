import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/app_tools.dart';
import '../application/document_session.dart';
import '../application/editor_controller.dart';
import '../application/garden_controller.dart';
import '../application/toasts.dart';
import '../application/tools.dart';
import '../application/workspace_settings.dart';
import '../platform/leave_guard.dart';
import '../platform/persistent_storage.dart';
import 'plan_header.dart';
import 'plan_status_bar.dart';
import 'canvas/drawing_canvas.dart';
import 'dialogs.dart';
import 'panels/layer_actions.dart';
import 'panels/greenhouse_panel.dart' as plant;
import 'panels/layers_panel.dart';
import 'panels/operations_panel.dart';
import 'panels/preferences_panel.dart';
import 'panels/properties_panel.dart';
import 'panels/seeds_panel.dart';
import 'panels/settings_panel.dart';
import 'panels/tools_panel.dart';
import 'theme.dart';
import 'widgets/dock.dart';
import 'widgets/panel.dart';
import 'widgets/text_focus.dart';
import 'widgets/toaster.dart';

/// Smallest window the editor supports, in logical pixels.
const Size minimumEditorSize = Size(800, 600);

/// The Plan screen: a header with menus, the drawing canvas between two
/// folding docks of panels, and a status bar.
class PlanScreen extends StatefulWidget {
  const PlanScreen({
    super.key,
    required this.session,
    this.navigator,
    this.garden,
  });

  final DocumentSession session;

  /// The Seed Vault, listed in Plant mode's Seeds panel; null shows it
  /// empty.
  final GardenController? garden;

  /// Switches to the other tools from the header; null shows Plan alone.
  final AppNavigator? navigator;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'canvas');

  /// The screen's own focus, taken back whenever Plan is opened again so
  /// its shortcuts work at once.
  final FocusNode _screenFocus = FocusNode(debugLabel: 'build screen');
  late final AppLifecycleListener _lifecycle;

  DocumentSession get _session => widget.session;
  EditorController get _editor => _session.editor;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
    _editor.addListener(_onEditorChanged);
    widget.navigator?.addListener(_onToolChanged);
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
    widget.navigator?.removeListener(_onToolChanged);
    _screenFocus.dispose();
    _session.removeListener(_onSessionChanged);
    _editor.removeListener(_onEditorChanged);
    _canvasFocus.dispose();
    super.dispose();
  }

  EditorController? _listened;

  bool get _isOpen =>
      widget.navigator == null || widget.navigator!.current == AppTool.plan;

  void _onToolChanged() {
    if (_isOpen) {
      _screenFocus.requestFocus();
    } else {
      // Leaving Plan drops a half-made shape, as Esc does, and keeps the
      // view in case the tab is closed from another tool.
      _editor.cancelOperation();
      unawaited(_session.rememberWorkspace());
    }
  }

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
      case LogicalKeyboardKey.keyD:
        _editor.selectTool(Tool.ground);
      case LogicalKeyboardKey.keyF:
        _editor.selectTool(Tool.feature);
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
      PanelId.seeds => DockPanel(
        index: index,
        title: id.label,
        expanded: expanded,
        onExpandedChanged: setExpanded,
        child: SeedsBody(editor: editor, garden: widget.garden),
      ),
      PanelId.greenhouse => DockPanel(
        index: index,
        title: id.label,
        expanded: expanded,
        onExpandedChanged: setExpanded,
        child: plant.GreenhouseBody(garden: widget.garden),
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
        subtitle: editor.showsFeature
            ? editor.selectedFeature!.kind.label
            : editor.showsReference
            ? 'Reference'
            : editor.selectedLayer?.role.label,
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
      focusNode: _screenFocus,
      autofocus: true,
      onKeyEvent: (node, event) =>
          _isOpen ? _onKey(node, event) : KeyEventResult.ignored,
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
                    PlanHeader(
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
                      navigator: widget.navigator,
                    ),
                    Expanded(
                      child: tooSmall ? const _TooSmallNotice() : _workspace(),
                    ),
                    PlanStatusBar(editor: _editor),
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
