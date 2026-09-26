import '../domain/layer.dart';

/// What a tool function does with pointer input.
enum ToolFunction {
  select('Select', 'select.svg'),
  place('Place', 'point-place.svg'),
  draw('Draw', 'line.svg'),
  join('Join', 'point-connect.svg'),

  /// Click the start, a point the arc passes through, then the end.
  arc('Arc', 'arc.svg'),
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

  /// Pattern functions: click inside one of the layer's closed shapes to
  /// fill the whole layer. None removes it.
  noPattern('None', 'fill-none.svg'),
  diagonalPattern('Diagonal', 'fill-diagonal.svg'),
  rowsPattern('Rows', 'fill-rows.svg'),
  crosshatchPattern('Crosshatch', 'fill-crosshatch.svg'),
  gridPattern('Grid', 'fill-grid.svg'),
  dotsPattern('Dots', 'fill-dots.svg'),
  crossesPattern('Crosses', 'fill-crosses.svg'),

  /// Click two points on the reference image a known distance apart.
  referenceLine('Ref. line', 'reference-line.svg');

  const ToolFunction(this.label, this.icon);

  final String label;
  final String icon;

  /// The pattern a Pattern function applies; null for None and for
  /// functions of other tools.
  FillPattern? get fillPattern => switch (this) {
    diagonalPattern => FillPattern.diagonal,
    rowsPattern => FillPattern.rows,
    crosshatchPattern => FillPattern.crosshatch,
    gridPattern => FillPattern.grid,
    dotsPattern => FillPattern.dots,
    crossesPattern => FillPattern.crosses,
    _ => null,
  };

  /// Select drags what is under the pointer; the others act on a click.
  /// Moving and resizing are done with Select.
  bool get drags => this == select;

  bool get drawsCircle => this == centerCircle || this == twoPointCircle;
}

/// The drawing tools, in the order the Tools panel shows them.
enum Tool {
  /// Picks, moves, and resizes anything on any unlocked layer.
  select('Select', 'select.svg', [ToolFunction.select]),
  point('Point', 'point.svg', [ToolFunction.place, ToolFunction.delete]),
  line('Line', 'line.svg', [
    ToolFunction.draw,
    ToolFunction.join,
    ToolFunction.delete,
  ]),

  /// Draws one circular-arc edge through three clicks.
  arc('Arc', 'arc.svg', [ToolFunction.arc]),

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

  /// Decorates all of the selected layer's land. Looks only: area and
  /// land rules are unchanged.
  pattern('Pattern', 'fill.svg', [
    ToolFunction.noPattern,
    ToolFunction.diagonalPattern,
    ToolFunction.rowsPattern,
    ToolFunction.crosshatchPattern,
    ToolFunction.gridPattern,
    ToolFunction.dotsPattern,
    ToolFunction.crossesPattern,
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

  /// Select picks and moves existing things, so it shows an arrow on the
  /// canvas. Every other tool adds or removes geometry and shows a
  /// crosshair.
  bool get usesArrowCursor => this == select;
}
