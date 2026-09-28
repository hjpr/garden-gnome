import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/curve_handles.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/hit_testing.dart';
import 'package:garden_gnome/application/previews.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/bezier.dart';
import 'package:garden_gnome/domain/geometry.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/persistence/document_codec.dart';

/// With the camera at its starting height over the origin, one metre is 30
/// pixels.
Offset at(double x, double y) => Offset(x * 30, y * 30);

void click(CanvasInput input, Offset where) {
  input.hover(where);
  input.press(where, shift: false);
  input.release(where);
}

/// Presses at [from], drags to [to] in small steps, and lets go there.
void drag(CanvasInput input, Offset from, Offset to) {
  input.hover(from);
  input.press(from, shift: false);
  for (var i = 1; i <= 4; i++) {
    input.move(Offset.lerp(from, to, i / 4)!);
  }
  input.release(to);
}

(EditorController, CanvasInput, String) curveEditor() {
  final editor = EditorController()..addLayer(LayerKind.property);
  addTearDown(editor.dispose);
  editor.selectTool(Tool.line);
  editor.selectFunction(ToolFunction.curve);
  return (editor, CanvasInput(editor), editor.selectedLayerId!);
}

/// Area inside a closed run of lines, from a dense walk along the true
/// curves. Independent of the arc stand-ins the app measures with.
double sampledArea(Geometry geometry, List<SegmentRef> ring) {
  final walk = <Vec>[];
  for (final ref in ring) {
    final line = geometry.lines[ref.segmentId]!;
    final bezier = line.bezier(geometry.points);
    final a = geometry.points[line.start]!;
    final b = geometry.points[line.end]!;
    final samples = [
      for (var i = 0; i < 2000; i++)
        bezier?.pointAt(i / 2000) ?? a + (b - a) * (i / 2000),
    ];
    if (ref.reversed) {
      final end = bezier?.pointAt(1) ?? b;
      walk.addAll([end, ...samples.skip(1).toList().reversed]);
    } else {
      walk.addAll(samples);
    }
  }
  var twice = 0.0;
  for (var i = 0; i < walk.length; i++) {
    twice += walk[i].cross(walk[(i + 1) % walk.length]);
  }
  return twice.abs() / 2;
}

/// A closed lens: a straight run out, then a curve back pulled down.
(EditorController, CanvasInput, String) lens() {
  final (editor, input, layer) = curveEditor();
  click(input, at(2, 5));
  drag(input, at(12, 5), at(12, 9));
  click(input, at(2, 5));
  return (editor, input, layer);
}

void main() {
  group('Bézier maths', () {
    const curve = CubicBezier(Vec(0, 0), Vec(0, 6), Vec(10, -6), Vec(10, 0));

    test('the stand-in arcs stay within half a millimetre', () {
      final edges = curve.toEdges();
      expect(edges.first.start, curve.p0);
      expect(edges.last.end, curve.p3);
      for (var i = 1; i < edges.length; i++) {
        expect(edges[i].start, edges[i - 1].end);
      }
      for (var i = 0; i <= 200; i++) {
        final p = curve.pointAt(i / 200);
        final gap = edges
            .map((e) => e.distanceTo(p))
            .reduce((a, b) => a < b ? a : b);
        expect(gap, lessThanOrEqualTo(bezierTolerance * 1.01));
      }
    });

    test('splitting keeps the same curve', () {
      final (first, second) = curve.split(0.3);
      expect(first.pointAt(1), second.pointAt(0));
      expect(
        first.pointAt(0.5).distanceTo(curve.pointAt(0.15)),
        lessThan(1e-12),
      );
      expect(
        second.pointAt(0.5).distanceTo(curve.pointAt(0.65)),
        lessThan(1e-12),
      );
    });

    test('the nearest point is found on the curve', () {
      final t = curve.closestParameter(curve.pointAt(0.42) + const Vec(0, 0));
      expect(t, closeTo(0.42, 1e-6));
    });
  });

  group('Line → Curve', () {
    test('Line offers only Straight and Curve', () {
      expect(Tool.line.functions, [ToolFunction.draw, ToolFunction.curve]);
      expect(ToolFunction.draw.label, 'Straight');
      expect(ToolFunction.curve.label, 'Curve');
    });

    test('plain clicks make sharp corners joined by straight lines', () {
      final (editor, input, layer) = curveEditor();
      for (final p in [at(0, 0), at(6, 0), at(6, 6), at(0, 0)]) {
        click(input, p);
      }
      final geometry = editor.document.geometryOf(layer);
      expect(geometry.lines, hasLength(3));
      expect(geometry.lines.values.every((l) => l.isStraight), isTrue);
      expect(geometry.region!.area, closeTo(18, 1e-9));
      expect(editor.lineAnchor, isNull, reason: 'closing ends the drawing');
    });

    test('dragging pulls out mirrored handles on both sides of a point', () {
      final (editor, input, layer) = curveEditor();
      click(input, at(0, 0));
      drag(input, at(10, 0), at(10, 3));
      var geometry = editor.document.geometryOf(layer);
      final first = geometry.lines.values.single;
      expect(first.isBezier, isTrue);
      expect(first.startHandle, Vec.zero, reason: 'the first point is sharp');
      expect(first.endHandle!.distanceTo(const Vec(0, -3)), lessThan(1e-9));
      expect(editor.curveHandle.distanceTo(const Vec(0, 3)), lessThan(1e-9));

      click(input, at(20, 0));
      geometry = editor.document.geometryOf(layer);
      final second = geometry.lines.values.last;
      expect(second.startHandle!.distanceTo(const Vec(0, 3)), lessThan(1e-9));
      expect(second.endHandle, Vec.zero);
    });

    test('the dashed preview follows the handle while dragging', () {
      final (editor, input, _) = curveEditor();
      click(input, at(0, 0));
      input.hover(at(10, 0));
      input.press(at(10, 0), shift: false);
      input.move(at(10, 1));
      input.move(at(10, 3));
      final preview = editor.preview as CurvePreview;
      expect(preview.from, const Vec(0, 0));
      expect(preview.outHandle.distanceTo(const Vec(10, 3)), lessThan(1e-9));
      expect(preview.toHandle.distanceTo(const Vec(10, -3)), lessThan(1e-9));
      expect(input.isDragging, isTrue, reason: 'the canvas does not pan');
      input.release(at(10, 3));
    });

    test('a closed curve is land whose area matches the true curve', () {
      final (editor, _, layer) = lens();
      final geometry = editor.document.geometryOf(layer);
      expect(geometry.isClosed, isTrue);
      expect(editor.document.isActive(layer), isTrue);
      final ring = geometry.shapes.values.single.segments;
      final truth = sampledArea(geometry, ring);
      // Both pieces bend, one each side of the chord: a handle 4 m long
      // on a 10 m chord adds 12 m² on each side.
      expect(truth, closeTo(24, 0.01));
      expect(geometry.region!.area, closeTo(truth, 0.01));
    });

    test('Undo takes back one piece at a time, then the first point', () {
      final (editor, input, layer) = curveEditor();
      click(input, at(0, 0));
      drag(input, at(10, 0), at(10, 3));
      click(input, at(20, 0));
      editor.undo();
      expect(editor.document.geometryOf(layer).lines, hasLength(1));
      expect(editor.lineAnchor, isNotNull, reason: 'still drawing');
      editor.undo();
      editor.undo();
      expect(editor.document.geometryOf(layer).points, isEmpty);
    });

    test('Esc ends the drawing and forgets the pulled-out handle', () {
      final (editor, input, _) = curveEditor();
      click(input, at(0, 0));
      drag(input, at(10, 0), at(10, 3));
      editor.escape();
      expect(editor.lineAnchor, isNull);
      expect(editor.curveHandle, Vec.zero);
    });

    test('a curve can join an existing open end', () {
      final (editor, input, layer) = curveEditor();
      editor.selectFunction(ToolFunction.draw);
      click(input, at(0, 0));
      click(input, at(10, 0));
      editor.escape();
      editor.selectFunction(ToolFunction.curve);
      click(input, at(10, 0));
      drag(input, at(0, 0), at(-3, 0));
      final geometry = editor.document.geometryOf(layer);
      expect(geometry.points, hasLength(2));
      expect(geometry.isClosed, isTrue);
    });

    test('a curve that crosses a line is kept but marks the layer invalid', () {
      final (editor, input, layer) = curveEditor();
      editor.selectFunction(ToolFunction.draw);
      click(input, at(5, -5));
      click(input, at(5, 5));
      editor.escape();
      editor.selectFunction(ToolFunction.curve);
      click(input, at(0, 0));
      drag(input, at(10, 0), at(10, -6));
      expect(editor.document.geometryOf(layer).lines, hasLength(2));
      expect(editor.document.ruleProblemOf(layer), isNotNull);
    });
  });

  group('Curves elsewhere in the editor', () {
    test('hit testing follows the curve, not its chord', () {
      final (editor, _, layer) = lens();
      final geometry = editor.document.geometryOf(layer);
      final curved = geometry.lines.values.firstWhere((l) => l.isBezier);
      final bulge = curved.bezier(geometry.points)!.pointAt(0.5);
      expect(
        lineAt(geometry, editor.camera, editor.camera.toScreen(bulge)),
        curved.id,
      );
    });

    test('Point → Place splits a curve into two that trace it exactly', () {
      final (editor, input, layer) = lens();
      final geometry = editor.document.geometryOf(layer);
      final curved = geometry.lines.values.firstWhere((l) => l.isBezier);
      final original = curved.bezier(geometry.points)!;
      final spot = original.pointAt(0.4);
      editor.selectTool(Tool.point);
      click(input, editor.camera.toScreen(spot));
      final split = editor.document.geometryOf(layer);
      expect(split.lines.containsKey(curved.id), isFalse);
      final halves = [
        for (final line in split.lines.values)
          if (!geometry.lines.containsKey(line.id)) line,
      ];
      expect(halves, hasLength(2));
      expect(halves.every((l) => l.isBezier), isTrue);
      for (final half in halves) {
        final b = half.bezier(split.points)!;
        for (final t in [0.25, 0.5, 0.75]) {
          final p = b.pointAt(t);
          expect(
            original.pointAt(original.closestParameter(p)).distanceTo(p),
            lessThan(1e-6),
          );
        }
      }
      expect(split.isClosed, isTrue);
    });

    test('Select shows the handles of a selected curve and drags them', () {
      final (editor, input, layer) = lens();
      editor.selectTool(Tool.select);
      final geometry = editor.document.geometryOf(layer);
      final curved = geometry.lines.values.firstWhere((l) => l.isBezier);
      editor.selectItem(curved.id);
      final handles = visibleCurveHandles(editor);
      expect(handles, hasLength(1), reason: 'the sharp end has none');
      final handle = handles.single;
      final before = editor.document;

      drag(
        input,
        editor.camera.toScreen(handle.tip),
        editor.camera.toScreen(handle.tip + const Vec(0, 2)),
      );
      final moved = editor.document.geometryOf(layer).lines[curved.id]!;
      expect(
        moved
            .handleAt(handle.pointId)!
            .distanceTo(handle.tip - handle.anchor + const Vec(0, 2)),
        lessThan(1e-9),
      );
      expect(editor.selection, {curved.id}, reason: 'selection unchanged');
      editor.undo();
      expect(sameContent(editor.document, before), isTrue);
    });

    test('moving a smooth point handle swings its partner round', () {
      final (editor, input, layer) = curveEditor();
      click(input, at(0, 0));
      drag(input, at(10, 0), at(10, 3));
      click(input, at(20, 0));
      editor.selectTool(Tool.select);
      final geometry = editor.document.geometryOf(layer);
      final smooth = geometry.points.entries
          .firstWhere((e) => e.value == const Vec(10, 0))
          .key;
      editor.selectItem(smooth);
      final handles = visibleCurveHandles(editor);
      expect(handles, hasLength(2));
      final grabbed = handles.first;
      drag(
        input,
        editor.camera.toScreen(grabbed.tip),
        editor.camera.toScreen(grabbed.anchor + const Vec(3, 0)),
      );
      final after = editor.document.geometryOf(layer);
      final offsets = [
        for (final line in after.linesAt(smooth)) line.handleAt(smooth)!,
      ];
      expect(offsets[0].cross(offsets[1]).abs(), lessThan(1e-9));
      expect(offsets[0].dot(offsets[1]), lessThan(0), reason: 'still smooth');
      expect(offsets.map((o) => o.length), everyElement(closeTo(3, 1e-9)));
    });

    test('rotating a curved shape turns its handles too', () {
      final (editor, input, layer) = lens();
      final beforeArea = editor.document.geometryOf(layer).region!.area;
      editor.selectTool(Tool.select);
      final geometry = editor.document.geometryOf(layer);
      editor.selectItem(geometry.shapes.keys.single);
      final moved = editor.document.withGeometry(
        geometry.edit((e) {
          // A quarter turn about the origin, as the rotate handle does.
          Vec turn(Vec p) => Vec(-p.y, p.x);
          for (final entry in geometry.points.entries) {
            e.movePoint(entry.key, turn(entry.value));
          }
          for (final line in geometry.lines.values) {
            if (!line.isBezier) continue;
            for (final end in [line.start, line.end]) {
              e.setHandle(line.id, end, turn(line.handleAt(end)!));
            }
          }
        }),
      );
      expect(moved.geometryOf(layer).region!.area, closeTo(beforeArea, 1e-6));
    });

    test('curves and their handles survive save and reopen', () {
      final (editor, _, layer) = lens();
      final opened = decodeGgnome(encodeGgnome(editor.document));
      expect(documentToJson(opened)['schema_version'], schemaVersion);
      final a = editor.document.geometryOf(layer);
      final b = opened.geometryOf(layer);
      for (final line in a.lines.values) {
        expect(b.lines[line.id]!.startHandle, line.startHandle);
        expect(b.lines[line.id]!.endHandle, line.endHandle);
      }
      expect(b.region!.area, closeTo(a.region!.area, 1e-9));
    });

    test('changing only a handle counts as an unsaved change', () {
      final (editor, _, layer) = lens();
      final geometry = editor.document.geometryOf(layer);
      final curved = geometry.lines.values.firstWhere((l) => l.isBezier);
      final changed = editor.document.withGeometry(
        geometry.edit(
          (e) => e.setHandle(curved.id, curved.end, const Vec(1, 1)),
        ),
      );
      expect(sameContent(changed, editor.document), isFalse);
    });
  });
}
