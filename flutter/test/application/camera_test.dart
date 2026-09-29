import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/domain/units.dart';
import 'package:garden_gnome/domain/vec.dart';

double feet(double metres) => Units.feet.fromMetres(metres);

void main() {
  test('a new view starts 100 ft up at 30 pixels a metre', () {
    const camera = Camera();
    expect(feet(camera.height), closeTo(100, 1e-9));
    expect(camera.pixelsPerMetreNow, pixelsPerMetre);
    expect(feet(camera.gridCellMetres(Units.feet)), closeTo(5, 1e-9));
    expect(camera.gridCellMetres(Units.metres), 1);
  });

  test('half the height shows the ground twice as large', () {
    const camera = Camera(height: Camera.startHeight / 2);
    expect(camera.pixelsPerMetreNow, closeTo(2 * pixelsPerMetre, 1e-9));
    expect(camera.gridCellMetres(Units.metres), 0.5);
  });

  test('closer in, the feet grid steps down to 1 ft', () {
    const camera = Camera(height: Camera.startHeight / 4);
    expect(feet(camera.gridCellMetres(Units.feet)), closeTo(1, 1e-9));
  });

  test('grid cells are round lengths in the units shown', () {
    const limits = HeightLimits();
    final feetSeen = <double>{};
    final metresSeen = <double>{};
    var camera = Camera(height: limits.lowest);
    while (true) {
      final ft = camera.gridCellMetres(Units.feet);
      final m = camera.gridCellMetres(Units.metres);
      feetSeen.add(double.parse(feet(ft).toStringAsFixed(6)));
      metresSeen.add(m);
      expect(
        ft * camera.pixelsPerMetreNow,
        greaterThanOrEqualTo(minGridCellPixels),
      );
      if (camera.height >= limits.highest) break;
      camera = camera.zoomAt(Offset.zero, -1, limits: limits);
    }
    expect(feetSeen, {0.5, 1, 5, 10, 20});
    expect(metresSeen.every(gridSteps[Units.metres]!.contains), isTrue);
  });

  test('by default the camera stays between 5 ft and 500 ft', () {
    const limits = HeightLimits();
    var camera = const Camera();
    for (var i = 0; i < 100; i++) {
      camera = camera.zoomAt(Offset.zero, 1, limits: limits);
    }
    expect(feet(camera.height), closeTo(5, 1e-9));
    for (var i = 0; i < 100; i++) {
      camera = camera.zoomAt(Offset.zero, -1, limits: limits);
    }
    expect(feet(camera.height), closeTo(500, 1e-9));
  });

  test('zooming keeps the point under the pointer in place', () {
    const anchor = Offset(120, 80);
    const camera = Camera(topLeft: Vec(3, 4));
    final before = camera.toWorld(anchor);
    final lowered = camera.zoomAt(anchor, 3, limits: const HeightLimits());
    expect(lowered.height, lessThan(camera.height));
    final after = lowered.toWorld(anchor);
    expect(after.x, closeTo(before.x, 1e-9));
    expect(after.y, closeTo(before.y, 1e-9));
  });

  test('wheel steps past a limit change nothing', () {
    final editor = EditorController(
      camera: Camera(height: const HeightLimits().lowest),
    )..setViewportSize(const Size(600, 400));
    var fired = 0;
    editor.viewChanges.addListener(() => fired++);
    editor.zoomAt(const Offset(300, 200), 1);
    expect(fired, 0);
    editor.zoomAt(const Offset(300, 200), -1);
    expect(fired, 1);
  });

  group('height limits', () {
    WorkspaceSettings limited(double lowest, double highest) =>
        WorkspaceSettings(
          appearance: Appearance(
            heightLimits: HeightLimits(lowest: lowest, highest: highest),
          ),
        );

    test('narrower limits move a camera that is out of range', () {
      final editor = EditorController()..setViewportSize(const Size(600, 400));
      editor.updateSettings(limited(40, 80));
      expect(editor.camera.height, 40);
      editor.updateSettings(limited(1, 10));
      expect(editor.camera.height, 10);
    });

    test('wheel zoom stops at the chosen limits', () {
      final editor = EditorController(settings: limited(2, 1000))
        ..setViewportSize(const Size(600, 400));
      for (var i = 0; i < 100; i++) {
        editor.zoomAt(const Offset(300, 200), -1);
      }
      expect(editor.camera.height, closeTo(1000, 1e-9));
      for (var i = 0; i < 100; i++) {
        editor.zoomAt(const Offset(300, 200), 1);
      }
      expect(editor.camera.height, closeTo(2, 1e-9));
    });

    test('Reset view starts within the limits', () {
      final editor = EditorController(settings: limited(1, 10))
        ..setViewportSize(const Size(600, 400));
      editor.resetView();
      expect(editor.camera.height, 10);
    });

    test('the lowest must be above 0 and below the highest', () {
      expect(limited(0, 10).appearance.problem, contains('more than 0'));
      expect(limited(10, 10).appearance.problem, contains('above the lowest'));
      expect(limited(20, 10).appearance.problem, contains('above the lowest'));
      expect(limited(1, double.infinity).appearance.problem, isNotNull);
      expect(limited(1, 1000).appearance.problem, isNull);
    });
  });
}
