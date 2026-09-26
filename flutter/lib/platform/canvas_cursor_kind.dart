/// Cursors the canvas sets itself, beyond what the widget tree picks.
enum CanvasCursor {
  /// Leave the cursor to Flutter (crosshair, grab hand, ...).
  system,

  /// The arrow from the Select tool's icon.
  arrow,

  /// Scale diagonally, from a top-left or bottom-right handle.
  resizeDiagonalDown,

  /// Scale diagonally, from a top-right or bottom-left handle.
  resizeDiagonalUp,

  /// Scale left and right, from a side edge.
  resizeHorizontal,

  /// Scale up and down, from the top or bottom edge.
  resizeVertical,

  /// Turn the selection, from just outside a corner.
  rotate,

  /// Select → Lasso: a rope loop, drawn from the Lasso icon.
  lasso,
}
