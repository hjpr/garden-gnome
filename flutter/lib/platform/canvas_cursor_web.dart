import 'package:web/web.dart' as web;

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

final String _arrowCursor =
    'url("data:image/svg+xml,${Uri.encodeComponent(_arrowSvg)}") 6 3, default';

bool _showing = false;

void showSelectArrowCursor(bool show) {
  if (show == _showing) return;
  final view = web.document.querySelector('flutter-view') as web.HTMLElement?;
  if (view == null) return;
  _showing = show;
  // Flutter sets its cursors on <body>; a value on this child wins while set.
  if (show) {
    view.style.cursor = _arrowCursor;
  } else {
    view.style.removeProperty('cursor');
  }
}
