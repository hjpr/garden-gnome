import '../domain/units.dart';
import 'camera.dart';

enum MenuScale {
  small('Small', 0.85),
  medium('Medium', 1),
  large('Large', 1.15);

  const MenuScale(this.label, this.factor);

  final String label;
  final double factor;
}

/// The two docks at the window edges that hold the panels.
enum DockSide { left, right }

/// The panels shown in the docks.
enum PanelId {
  tools('Drawing tools', DockSide.left),

  /// Actions on the selected shapes, such as Boolean Union and Subtract.
  operations('Operations', DockSide.left),
  settings('Controls', DockSide.left),
  properties('Properties', DockSide.right),
  layers('Layers', DockSide.right);

  const PanelId(this.label, this.side);

  final String label;

  /// The dock the panel lives in.
  final DockSide side;
}

/// Which docks are open and the top-to-bottom order of panels in each.
class DockLayout {
  const DockLayout({
    this.left = const [PanelId.tools, PanelId.operations, PanelId.settings],
    this.right = const [PanelId.properties, PanelId.layers],
    this.folded = const {},
    this.widths = const {},
  });

  /// Narrowest and widest a dock's panel column may be dragged, in
  /// logical pixels at Medium menu size.
  static const double minWidth = 200;
  static const double maxWidth = 520;

  /// Width of each dock's panel column when nothing has been dragged.
  static const Map<DockSide, double> defaultWidths = {
    DockSide.left: 232,
    DockSide.right: 264,
  };

  /// Rebuilds a layout from saved names, keeping only known panels on
  /// their own side. A panel missing from an older saved layout is put
  /// back after the panel it follows by default (or at the end), so a new
  /// panel such as Operations appears where it is meant to.
  factory DockLayout.restore({
    List<String> left = const [],
    List<String> right = const [],
    List<String> folded = const [],
    Map<String, double> widths = const {},
  }) {
    List<PanelId> side(DockSide dock, List<String> names) {
      final order = <PanelId>[
        for (final name in names)
          for (final id in PanelId.values)
            if (id.name == name && id.side == dock) id,
      ];
      final result = order.toSet().toList();
      PanelId? previous;
      for (final id in PanelId.values.where((id) => id.side == dock)) {
        if (!result.contains(id)) {
          result.insert(
            previous == null ? result.length : result.indexOf(previous) + 1,
            id,
          );
        }
        previous = id;
      }
      return result;
    }

    return DockLayout(
      left: side(DockSide.left, left),
      right: side(DockSide.right, right),
      folded: {
        for (final name in folded)
          for (final dock in DockSide.values)
            if (dock.name == name) dock,
      },
      widths: {
        for (final dock in DockSide.values)
          if (widths[dock.name] case final w? when w.isFinite)
            dock: w.clamp(minWidth, maxWidth),
      },
    );
  }

  final List<PanelId> left;
  final List<PanelId> right;

  /// Docks folded down to their slim rail.
  final Set<DockSide> folded;

  /// Widths the user dragged each dock to. Kept while the dock is folded,
  /// so it reopens at the same width.
  final Map<DockSide, double> widths;

  double widthOf(DockSide side) => widths[side] ?? defaultWidths[side]!;

  DockLayout withWidth(DockSide side, double width) => DockLayout(
    left: left,
    right: right,
    folded: folded,
    widths: {...widths, side: width.clamp(minWidth, maxWidth)},
  );

  List<PanelId> orderOf(DockSide side) => side == DockSide.left ? left : right;

  bool isOpen(DockSide side) => !folded.contains(side);

  DockLayout withOpen(DockSide side, bool open) => DockLayout(
    left: left,
    right: right,
    folded: open ? ({...folded}..remove(side)) : {...folded, side},
    widths: widths,
  );

  /// Moves a panel within the [visible] panels of [side], where [from] and
  /// [to] are positions in [visible] (as a drag-to-reorder list reports
  /// them: [to] counts the dragged panel as still in place). Hidden panels
  /// keep their place relative to the others.
  DockLayout moved(DockSide side, List<PanelId> visible, int from, int to) {
    if (to > from) to -= 1;
    if (from == to || from < 0 || from >= visible.length) return this;
    final panel = visible[from];
    final rest = [...visible]..removeAt(from);
    final order = [...orderOf(side)]..remove(panel);
    final index = to >= rest.length
        ? order.length
        : order.indexOf(rest[to.clamp(0, rest.length - 1)]);
    order.insert(index, panel);
    return DockLayout(
      left: side == DockSide.left ? order : left,
      right: side == DockSide.right ? order : right,
      folded: folded,
      widths: widths,
    );
  }
}

/// Which edge of the window toasts appear at.
enum ToastPosition {
  top('Top'),
  bottom('Bottom');

  const ToastPosition(this.label);

  final String label;
}

/// Drawing styles and limits edited in Preferences and applied together.
class Appearance {
  const Appearance({
    this.lineWidth = 2,
    this.gridThickness = 1,
    this.gridColor = 0xFFDCE0D6,
    this.gridOpacity = 1,
    this.heightLimits = const HeightLimits(),
    this.historyCapacity = 50,
    this.toastPosition = ToastPosition.bottom,
  });

  /// Outline width in logical pixels.
  final double lineWidth;
  final double gridThickness;
  final int gridColor;

  /// 0 (invisible) to 1 (opaque).
  final double gridOpacity;
  final HeightLimits heightLimits;

  /// Undo and Redo steps kept together.
  final int historyCapacity;

  /// Where toasts appear.
  final ToastPosition toastPosition;

  Appearance withToastPosition(ToastPosition position) => Appearance(
    lineWidth: lineWidth,
    gridThickness: gridThickness,
    gridColor: gridColor,
    gridOpacity: gridOpacity,
    heightLimits: heightLimits,
    historyCapacity: historyCapacity,
    toastPosition: position,
  );

  /// Returns a reason the settings cannot be applied, or null when valid.
  String? get problem {
    if (!(lineWidth > 0) || !lineWidth.isFinite) {
      return 'Line width must be more than 0';
    }
    if (!(gridThickness > 0) || !gridThickness.isFinite) {
      return 'Grid thickness must be more than 0';
    }
    if (!(gridOpacity >= 0 && gridOpacity <= 1)) {
      return 'Grid opacity must be between 0 and 100%';
    }
    if (!(heightLimits.lowest > 0)) {
      return 'Lowest camera height must be more than 0';
    }
    if (!(heightLimits.highest > heightLimits.lowest) ||
        !heightLimits.highest.isFinite) {
      return 'Highest camera height must be above the lowest';
    }
    if (historyCapacity < 1 || historyCapacity > 1000) {
      return 'Undo steps must be between 1 and 1000';
    }
    return null;
  }
}

/// Per-drawing workspace choices. Saved separately from the drawing itself.
class WorkspaceSettings {
  const WorkspaceSettings({
    this.units = Units.feet,
    this.areaUnits = AreaUnits.squareFeet,
    this.snappingEnabled = false,
    this.guidesEnabled = false,
    this.menuScale = MenuScale.medium,
    this.appearance = const Appearance(),
    this.hiddenPanels = const {},
    this.minimizedPanels = const {},
    this.docks = const DockLayout(),
  });

  /// How lengths are shown.
  final Units units;

  /// How areas are shown.
  final AreaUnits areaUnits;

  /// Snap new and moved positions to the grid.
  final bool snappingEnabled;

  /// Line positions up with the geometry last hovered; see guides.dart.
  final bool guidesEnabled;
  final MenuScale menuScale;
  final Appearance appearance;
  final Set<PanelId> hiddenPanels;

  /// Panels collapsed to their heading inside their dock.
  final Set<PanelId> minimizedPanels;
  final DockLayout docks;

  WorkspaceSettings copyWith({
    Units? units,
    AreaUnits? areaUnits,
    bool? snappingEnabled,
    bool? guidesEnabled,
    MenuScale? menuScale,
    Appearance? appearance,
    Set<PanelId>? hiddenPanels,
    Set<PanelId>? minimizedPanels,
    DockLayout? docks,
  }) => WorkspaceSettings(
    units: units ?? this.units,
    areaUnits: areaUnits ?? this.areaUnits,
    snappingEnabled: snappingEnabled ?? this.snappingEnabled,
    guidesEnabled: guidesEnabled ?? this.guidesEnabled,
    menuScale: menuScale ?? this.menuScale,
    appearance: appearance ?? this.appearance,
    hiddenPanels: hiddenPanels ?? this.hiddenPanels,
    minimizedPanels: minimizedPanels ?? this.minimizedPanels,
    docks: docks ?? this.docks,
  );
}
