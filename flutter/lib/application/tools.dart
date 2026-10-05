import '../domain/feature.dart';
import '../domain/ground.dart';

/// What a tool function does with pointer input.
enum ToolFunction {
  /// Select → Marquee: drag a rectangle to select everything it touches.
  marquee('Marquee', 'marquee.svg'),

  /// Select → Lasso: drag any closed outline to select everything it
  /// touches.
  lasso('Lasso', 'lasso.svg'),
  place('Place', 'point-place.svg'),

  /// Click corners one after another. Clicking an existing point joins
  /// it, so there is no separate Join.
  draw('Straight', 'line.svg'),

  /// Pen style: click for a sharp corner, or press and drag to pull out
  /// Bézier handles that curve the line through that point.
  curve('Curve', 'line-curve.svg'),

  /// Click the start, a point the arc passes through, then the end.
  threePointArc('3-point', 'arc.svg'),

  /// Click the start, then the end, then the arc's middle, which sets how
  /// far it bends.
  startEndArc('Start-end', 'arc-start-end.svg'),
  delete('Delete', 'point-delete.svg'),

  /// Click the centre, then a point on the edge.
  centerCircle('Center', 'center-diameter-circle.svg'),

  /// Click the two ends of a diameter.
  twoPointCircle('2-point', 'two-point-circle.svg'),

  /// Click the centre, then one corner. The number of sides is set in
  /// the Tools panel.
  regularPolygon('Regular', 'polygon-regular.svg'),

  /// Click two opposite corners.
  rectangle('Rectangle', 'rectangle.svg'),

  /// Ground functions: click inside a bed to give it that ground. Fallow
  /// is unprepared dirt that nothing is planted on. Plantings are added
  /// in Layers.
  clearGround('Fallow', 'ground-zone.svg'),
  coverGround('Cover', 'ground-cover.svg'),
  flatGround('Flat', 'ground-flat.svg'),
  rowGround('Row', 'ground-row.svg'),

  /// Feature functions: click to place one at its usual size.
  raisedBed('Raised bed', 'raised-bed.svg'),
  greenhouse('Greenhouse', 'greenhouse.svg'),
  highTunnel('High tunnel', 'high-tunnel.svg'),

  /// Click two points on the reference image a known distance apart.
  referenceLine('Ref. line', 'reference-line.svg');

  const ToolFunction(this.label, this.icon);

  final String label;
  final String icon;

  /// Whether this is one of the Ground tool's functions.
  bool get setsGround =>
      this == clearGround ||
      this == coverGround ||
      this == flatGround ||
      this == rowGround;

  /// The ground a Ground function gives a bed; null for Fallow and
  /// for other tools. Check [setsGround] first.
  GroundType? get groundType => switch (this) {
    coverGround => GroundType.cover,
    flatGround => GroundType.flat,
    rowGround => GroundType.row,
    _ => null,
  };

  /// The feature a Feature function places; null for other tools.
  FeatureKind? get featureKind => switch (this) {
    raisedBed => FeatureKind.raisedBed,
    greenhouse => FeatureKind.greenhouse,
    highTunnel => FeatureKind.highTunnel,
    _ => null,
  };

  /// Select drags what is under the pointer, or draws a selection outline
  /// on empty ground; the others act on a click. Moving and resizing are
  /// done with Select.
  bool get drags => this == marquee || this == lasso;

  bool get drawsCircle => this == centerCircle || this == twoPointCircle;
}

/// The Plan screen's two modes, switched from the header.
///
/// Build lays out the land. Plant freezes all geometry while existing
/// grow zones can be selected and planted with seeds from the Seed Vault.
enum EditMode {
  build('Build'),
  plant('Plant');

  const EditMode(this.label);

  final String label;
}

/// The drawing tools, in the order the Tools panel shows them.
enum Tool {
  /// Picks, moves, and resizes anything on any unlocked layer.
  select('Select', 'select.svg', [ToolFunction.marquee, ToolFunction.lasso]),
  point('Point', 'point.svg', [ToolFunction.place, ToolFunction.delete]),

  /// Removing lines is done with Select and Delete.
  line('Line', 'line.svg', [ToolFunction.draw, ToolFunction.curve]),

  /// Draws one circular-arc edge in three clicks. The functions differ
  /// only in click order.
  arc('Arc', 'arc.svg', [ToolFunction.threePointArc, ToolFunction.startEndArc]),

  /// Draws a circle. Both functions make the same kind of
  /// circle: a centre point and a radius.
  circle('Circle', 'circle.svg', [
    ToolFunction.centerCircle,
    ToolFunction.twoPointCircle,
  ]),

  /// Draws a closed straight-edged shape in two clicks.
  polygon('Polygon', 'polygon.svg', [
    ToolFunction.regularPolygon,
    ToolFunction.rectangle,
  ]),

  /// Prepares a bed's soil: fallow, cover crop, flat, or in rows. Rows are sized in
  /// Properties.
  ground('Ground', 'ground.svg', [
    ToolFunction.clearGround,
    ToolFunction.coverGround,
    ToolFunction.flatGround,
    ToolFunction.rowGround,
  ]),

  /// Places raised beds, greenhouses and high tunnels. Their sizes are
  /// set in Properties.
  feature('Feature', 'feature.svg', [
    ToolFunction.raisedBed,
    ToolFunction.greenhouse,
    ToolFunction.highTunnel,
  ]),

  /// A picture to trace over. Upload it in Properties, move and scale it
  /// with Select, then draw a reference line and enter its real length
  /// to set the scale.
  reference('Reference', 'reference.svg', [ToolFunction.referenceLine]);

  const Tool(this.label, this.icon, this.functions);

  final String label;
  final String icon;

  /// Available functions; the first is used when the tool is first chosen.
  final List<ToolFunction> functions;

  /// Whether the tool's functions are listed under it. Reference lists
  /// its one function too, so Reference line is visible by name.
  bool get hasFunctionChoice => functions.length > 1 || this == reference;

  /// Plant selects existing grow zones; all drawing belongs to Build.
  bool availableIn(EditMode mode) => mode == EditMode.build || this == select;

  /// Select picks and moves existing things, so it shows an arrow on the
  /// canvas. Every other tool adds or removes geometry and shows a
  /// crosshair.
  bool get usesArrowCursor => this == select;
}
