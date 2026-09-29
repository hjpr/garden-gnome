import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/guides.dart';
import 'package:garden_gnome/application/previews.dart';
import 'package:garden_gnome/application/snapping.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/vec.dart';

/// With the camera at its starting height over the origin, one metre is 30
/// pixels, so guides reach 6 px = 0.2 m.
Offset at(double x, double y) => Offset(x * 30, y * 30);

void click(CanvasInput input, Offset where) {
  input.hover(where);
  input.press(where, shift: false);
  input.release(where);
}

/// Presses at [from] and drags to [to], returning the preview shown just
/// before release.
Preview? drag(
  EditorController editor,
  CanvasInput input,
  Offset from,
  Offset to,
) {
  input.hover(from);
  input.press(from, shift: false);
  input.move(from + (to - from) / 10);
  input.move(to);
  final preview = editor.preview;
  input.release(to);
  return preview;
}

class _Setup {
  _Setup() {
    editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    editor.guideMemory.clock = () => now;
    editor.updateSettings(editor.settings.copyWith(guidesEnabled: true));
    input = CanvasInput(editor);
    layer = editor.selectedLayerId!;
  }

  late final EditorController editor;
  late final CanvasInput input;
  late final String layer;
  DateTime now = DateTime(2026);

  /// Hovers [where] and keeps the pointer there past the dwell time.
  void rest(Offset where) {
    input.hover(where);
    now = now.add(GuideMemory.dwell);
    input.hover(where);
  }

  /// Hovers [where] only briefly, as when passing over it.
  void brush(Offset where) {
    input.hover(where);
    now = now.add(const Duration(milliseconds: 20));
    input.hover(at(20, 20));
  }

  void point(double x, double y) {
    editor.selectTool(Tool.point);
    click(input, at(x, y));
  }

  Vec pointNear(double x, double y) => editor.document
      .geometryOf(layer)
      .points
      .values
      .reduce(
        (a, b) => a.distanceTo(Vec(x, y)) < b.distanceTo(Vec(x, y)) ? a : b,
      );
}

/// Whether [guides] shows a straight guide through [through] running
/// along [direction] (either way round).
bool showsLine(SnapGuides guides, Vec through, Vec direction) =>
    guides.lines.whereType<GuideLine>().any(
      (g) =>
          g.distanceTo(through) < 1e-9 &&
          g.direction.cross(direction).abs() < 1e-9,
    );

/// A property with one straight line from (2, 2) to (6, 4), hovered long
/// enough to guide, and the Point tool chosen.
_Setup _hoveredSlopedLine() {
  final s = _Setup();
  s.editor.selectTool(Tool.line);
  click(s.input, at(2, 2));
  click(s.input, at(6, 4));
  s.editor.escape();
  s.rest(at(3, 2.5));
  s.editor.selectTool(Tool.point);
  return s;
}

void main() {
  test('dragging a point near the level of a hovered point lines it up', () {
    final s = _Setup()
      ..point(2, 2)
      ..point(6, 5);
    s.editor.selectTool(Tool.select);
    s.rest(at(2, 2));
    // Grabbing B hovers it too; B is moving, so A still guides.
    s.rest(at(6, 5));
    final preview = drag(s.editor, s.input, at(6, 5), at(9, 2.1));

    expect(preview!.guides.lines, hasLength(1));
    expect(showsLine(preview.guides, const Vec(2, 2), const Vec(1, 0)), isTrue);
    expect(s.pointNear(9, 2), const Vec(9, 2));
  });

  test('guides pull on both axes independently', () {
    final s = _Setup()
      ..point(2, 2)
      ..point(6, 5);
    s.editor.selectTool(Tool.select);
    s.rest(at(2, 2));
    drag(s.editor, s.input, at(6, 5), at(2.1, 8));
    expect(s.pointNear(2, 8), const Vec(2, 8));
  });

  test('passing briefly over other geometry does not replace the guide', () {
    final s = _Setup()
      ..point(2, 2)
      ..point(6, 5)
      ..point(4, 9);
    s.editor.selectTool(Tool.select);
    s.rest(at(2, 2));
    s.brush(at(4, 9));
    drag(s.editor, s.input, at(6, 5), at(9, 2.1));
    expect(s.pointNear(9, 2), const Vec(9, 2));
  });

  test('a line\'s midpoint locks on from farther away than a guide line', () {
    final s = _hoveredSlopedLine();
    // 8 px from the midpoint (4, 3): past a guide line's 6 px reach, but
    // inside the midpoint's 10 px.
    s.input.hover(at(4, 3) + const Offset(0, 8));
    final preview = s.editor.preview! as PointPreview;
    expect(preview.position, const Vec(4, 3));
    expect(preview.guides.mark, const Vec(4, 3));
  });

  test('a point placed on a line\'s midpoint by the guide splits the line', () {
    final s = _hoveredSlopedLine();
    final where = at(4, 3) + const Offset(0, 8);
    s.input.hover(where);
    expect((s.editor.preview! as PointPreview).valid, isTrue);
    click(s.input, where);
    final geometry = s.editor.document.geometryOf(s.layer);
    expect(geometry.lines, hasLength(2));
    expect(geometry.points.values, contains(const Vec(4, 3)));
  });

  test('a line guides along its own path, past its ends', () {
    final s = _hoveredSlopedLine();
    // On the line's extension at x = 10 is y = 6; hover just off it.
    s.input.hover(at(10, 6.1));
    final preview = s.editor.preview! as PointPreview;
    expect(preview.position.x, closeTo(10.04, 0.01));
    expect(preview.position.y - 2, closeTo((preview.position.x - 2) / 2, 1e-9));
    expect(showsLine(preview.guides, const Vec(2, 2), const Vec(2, 1)), isTrue);
  });

  test('a line guides along the perpendicular through its midpoint', () {
    final s = _hoveredSlopedLine();
    // The perpendicular through (4, 3) runs along (-1, 2): (3, 5) is on it.
    s.input.hover(at(3.1, 5));
    final preview = s.editor.preview! as PointPreview;
    final p = preview.position;
    expect((p - const Vec(4, 3)).dot(const Vec(2, 1)), closeTo(0, 1e-9));
    expect(
      showsLine(preview.guides, const Vec(4, 3), const Vec(-1, 2)),
      isTrue,
    );
  });

  test('a line\'s midpoint offers no horizontal or vertical guide', () {
    final s = _hoveredSlopedLine();
    // Level with the midpoint (4, 3) but well away from every line guide.
    s.input.hover(at(12, 3.1));
    final preview = s.editor.preview! as PointPreview;
    expect(preview.guides.isEmpty, isTrue);
    expect(preview.position, const Vec(12, 3.1));
  });

  test('an arc guides along its whole circle', () {
    final s = _Setup();
    s.editor.selectTool(Tool.arc);
    click(s.input, at(2, 5));
    click(s.input, at(5, 2));
    click(s.input, at(8, 5));
    s.rest(at(5, 2));
    s.editor.selectTool(Tool.point);
    // The arc's circle is centred (5, 5), radius 3; (5, 8) is on the
    // part the arc does not cover.
    s.input.hover(at(5.5, 8.05));
    final preview = s.editor.preview! as PointPreview;
    expect(preview.position.distanceTo(const Vec(5, 5)), closeTo(3, 1e-9));
    expect(preview.guides.lines.single, isA<GuideCircle>());
  });

  test('a hovered circle offers its outermost points without guide lines', () {
    final s = _Setup();
    s.editor.selectTool(Tool.circle);
    s.editor.selectFunction(ToolFunction.centerCircle);
    click(s.input, at(5, 5));
    click(s.input, at(7, 5));
    s.rest(at(3, 5));
    s.editor.selectTool(Tool.point);

    s.input.hover(at(5.1, 3.1));
    final onTop = s.editor.preview! as PointPreview;
    expect(onTop.position, const Vec(5, 3));
    expect(onTop.guides.mark, const Vec(5, 3));

    // In line with the top, but away from it: no horizontal/vertical pull.
    s.input.hover(at(5.1, 9));
    final below = s.editor.preview! as PointPreview;
    expect(below.position.x, closeTo(5.1, 1e-9));
    expect(below.guides.isEmpty, isTrue);
  });

  test('a moved shape lines up by whichever corner is closest', () {
    final s = _Setup()..point(10, 7);
    s.editor.selectTool(Tool.polygon);
    s.editor.selectFunction(ToolFunction.rectangle);
    click(s.input, at(2, 2));
    click(s.input, at(6, 4));
    s.editor.selectTool(Tool.select);
    s.rest(at(10, 7));
    // Down by about 3.1 m: the bottom edge (y = 4) lands near y = 7.
    final preview = drag(s.editor, s.input, at(4, 3), at(4.5, 6.1));
    expect(
      showsLine(preview!.guides, const Vec(10, 7), const Vec(1, 0)),
      isTrue,
    );
    expect(s.pointNear(2.5, 7), const Vec(2.5, 7));
  });

  test('with Guides off nothing is lined up', () {
    final s = _Setup();
    s.editor.updateSettings(s.editor.settings.copyWith(guidesEnabled: false));
    s
      ..point(2, 2)
      ..point(6, 5);
    s.editor.selectTool(Tool.select);
    s.rest(at(2, 2));
    final preview = drag(s.editor, s.input, at(6, 5), at(9, 2.1));
    expect(preview!.guides.isEmpty, isTrue);
    expect(s.pointNear(9, 2).y, closeTo(2.1, 1e-9));
  });

  test('a guide wins over the grid on its axis; the grid keeps the other', () {
    final s = _Setup()..point(2, 2.5);
    s.editor.updateSettings(s.editor.settings.copyWith(snappingEnabled: true));
    s.rest(at(2, 2.5));
    // The start view's grid is 5 ft, so x snaps to 15 ft.
    s.input.hover(at(4.4, 2.6));
    final preview = s.editor.preview! as PointPreview;
    expect(preview.position.x, closeTo(15 * 0.3048, 1e-9));
    expect(preview.position.y, 2.5);
  });
}
