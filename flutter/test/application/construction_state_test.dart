import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/construction_state.dart';
import 'package:garden_gnome/application/history.dart';
import 'package:garden_gnome/domain/vec.dart';

void main() {
  ConstructionState pending() => ConstructionState()
    ..startLine()
    ..lineAnchor = 'point-1'
    ..curveHandle = const Vec(1, 2)
    ..arcPoints.add(const ArcPoint(Vec(2, 3)))
    ..circleStart = const CircleStart(Vec(3, 4))
    ..polygonStart = const Vec(4, 5)
    ..referenceImageId = 'image-1'
    ..referenceStart = const Vec(5, 6);

  test('reset clears all unfinished input without recycling line tokens', () {
    final state = pending();
    final token = state.lineToken!;
    state.reset();
    expect(state.isActive, isFalse);
    expect(state.hasPendingClicks, isFalse);
    expect(state.curveHandle, Vec.zero);
    expect(state.referenceImageId, isNull);
    expect(state.startLine(), greaterThan(token));
  });

  test('history restores only the matching live line operation', () {
    final state = pending();
    final token = state.lineToken!;
    state.restoreLine(
      LineContext(operation: token),
      'point-2',
      drawingLine: true,
    );
    expect(state.lineToken, token);
    expect(state.lineAnchor, 'point-2');
    expect(state.hasPendingClicks, isFalse);
    expect(state.curveHandle, Vec.zero);
    state.restoreLine(
      LineContext(operation: token),
      'point-1',
      drawingLine: false,
    );
    expect(state.isActive, isFalse);
  });

  test('history from a previous operation cannot restart it', () {
    final state = pending();
    final previous = state.lineToken!;
    state.reset();
    state.startLine();
    state.restoreLine(
      LineContext(operation: previous),
      'point-1',
      drawingLine: true,
    );
    expect(state.isActive, isFalse);
  });
}
