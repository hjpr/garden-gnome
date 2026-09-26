import 'package:web/web.dart' as web;

import 'canvas_cursor_kind.dart';

/// The arrow from src/icons/select.svg, with a thin white edge so it stays
/// visible on dark land. The tip sits at (6, 3), which is the hot spot.
const _arrowSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24" stroke-linejoin="round">'
    '<path d="M6 3L6 19L10.5 14.8L14.2 21.4L16.8 20L13.2 13.6L19 13Z" '
    'fill="#000" stroke="#fff" stroke-width="2.6"/>'
    '<path d="M6 3L6 19L10.5 14.8L14.2 21.4L16.8 20L13.2 13.6L19 13Z" '
    'fill="#000" stroke="#000" stroke-width="1.2"/>'
    '</svg>';

/// A curved arrow turning around its centre, drawn black on a white
/// outline like the arrow. The hot spot is the middle.
const _rotateShape =
    '<path d="M6.3 15.5A6.5 6.5 0 1 1 15.5 17.7" fill="none" '
    'stroke-linecap="round" STROKE/>'
    '<path d="M13.2 14.4L17.4 18.3L12.2 20.4Z" stroke-linejoin="round" '
    'FILL/>';

final _rotateSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24">'
    '${_rotateShape.replaceFirst('STROKE', 'stroke="#fff" stroke-width="4.6"').replaceFirst('FILL', 'fill="#fff" stroke="#fff" stroke-width="2.6"')}'
    '${_rotateShape.replaceFirst('STROKE', 'stroke="#000" stroke-width="2"').replaceFirst('FILL', 'fill="#000" stroke="#000" stroke-width="0.6"')}'
    '</svg>';

/// The loop from src/icons/lasso.svg, black on a white edge like the
/// arrow. The hot spot is the end of the rope's tail, bottom left.
const _lassoPath =
    'M12 4.5C7.3 4.5 3.8 6.8 3.8 9.8C3.8 12.8 7.3 15 12 15C16.7 15 20.2 12.8 20.2 9.8C20.2 6.8 16.7 4.5 12 4.5Z M8.6 14.4C8 16 8.4 17.6 9.8 18.4C11 19.1 11.2 20.4 10.2 21.2';

const _lassoSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24" fill="none" stroke-linecap="round" '
    'stroke-linejoin="round">'
    '<path d="$_lassoPath" stroke="#fff" stroke-width="3.6"/>'
    '<path d="$_lassoPath" stroke="#000" stroke-width="1.6"/>'
    '</svg>';

String _svgCursor(String svg, int x, int y, String fallback) =>
    'url("data:image/svg+xml,${Uri.encodeComponent(svg)}") $x $y, $fallback';

final Map<CanvasCursor, String> _css = {
  CanvasCursor.arrow: _svgCursor(_arrowSvg, 6, 3, 'default'),
  CanvasCursor.resizeDiagonalDown: 'nwse-resize',
  CanvasCursor.resizeDiagonalUp: 'nesw-resize',
  CanvasCursor.resizeHorizontal: 'ew-resize',
  CanvasCursor.resizeVertical: 'ns-resize',
  CanvasCursor.rotate: _svgCursor(_rotateSvg, 12, 12, 'crosshair'),
  CanvasCursor.lasso: _svgCursor(_lassoSvg, 10, 21, 'crosshair'),
};

CanvasCursor _showing = CanvasCursor.system;

void showCanvasCursor(CanvasCursor cursor) {
  if (cursor == _showing) return;
  final view = web.document.querySelector('flutter-view') as web.HTMLElement?;
  if (view == null) return;
  _showing = cursor;
  // Flutter sets its cursors on <body>; a value on this child wins while set.
  final css = _css[cursor];
  if (css == null) {
    view.style.removeProperty('cursor');
  } else {
    view.style.cursor = css;
  }
}
