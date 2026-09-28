import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/previews.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/reference_image.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/persistence/document_codec.dart';

/// Smallest valid PNG header bytes; enough for type sniffing. The codec
/// never decodes pictures, so tests do not need real pixels.
final png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4, //
]);

Offset at(Vec world, Camera camera) => camera.toScreen(world);

void click(CanvasInput input, Offset screen) {
  input.hover(screen);
  input.press(screen, shift: false);
  input.release(screen);
}

void drag(CanvasInput input, Offset from, Offset to) {
  input.press(from, shift: false);
  input.move(from + (to - from) / 2);
  input.move(to);
  input.release(to);
}

/// An editor with an 800×600 view at 100% and a 400×200 pixel picture
/// uploaded into it.
(EditorController, CanvasInput) withImage() {
  final editor = EditorController()..setViewportSize(const Size(800, 600));
  addTearDown(editor.dispose);
  final input = CanvasInput(editor);
  editor.selectTool(Tool.reference);
  editor.addReferenceImage(
    bytes: png,
    mimeType: 'image/png',
    pixelWidth: 400,
    pixelHeight: 200,
  );
  return (editor, input);
}

void main() {
  group('ReferenceImage', () {
    test('an upload fits 80% of the view, centred, uncalibrated', () {
      final image = ReferenceImage.fitted(
        id: 'image-1',
        bytes: png,
        mimeType: 'image/png',
        pixelWidth: 400,
        pixelHeight: 200,
        viewCentre: const Vec(10, 5),
        viewWidth: 20,
        viewHeight: 20,
      );
      expect(image.worldWidth, closeTo(16, 1e-9));
      expect(image.worldHeight, closeTo(8, 1e-9));
      expect(image.centre.distanceTo(const Vec(10, 5)), lessThan(1e-9));
      expect(image.isCalibrated, isFalse);
    });

    test('calibrating makes the line the entered length about its start', () {
      final image = ReferenceImage.fitted(
        id: 'image-1',
        bytes: png,
        mimeType: 'image/png',
        pixelWidth: 400,
        pixelHeight: 200,
        viewCentre: Vec.zero,
        viewWidth: 40,
        viewHeight: 40,
      ).withLine(const Vec(100, 50), const Vec(300, 50));
      final fixed = image.toWorld(image.lineStart!);
      final calibrated = image.calibratedTo(25);
      expect(calibrated.lineLength, closeTo(25, 1e-9));
      expect(calibrated.metresPerPixel, closeTo(25 / 200, 1e-12));
      expect(
        calibrated.toWorld(calibrated.lineStart!).distanceTo(fixed),
        lessThan(1e-9),
      );
      expect(calibrated.isCalibrated, isTrue);
      // Moving keeps the calibration; a hand scale or new line clears it.
      expect(calibrated.movedBy(const Vec(3, 4)).isCalibrated, isTrue);
      expect(
        calibrated.scaledAbout(calibrated.topLeft, 0.2).isCalibrated,
        isFalse,
      );
      expect(
        calibrated.withLine(Vec.zero, const Vec(10, 0)).knownDistance,
        isNull,
      );
    });

    test('file type comes from the bytes, not the name', () {
      expect(imageMimeType(png), 'image/png');
      expect(
        imageMimeType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0])),
        'image/jpeg',
      );
      expect(
        imageMimeType(Uint8List.fromList('RIFF....WEBP'.codeUnits)),
        'image/webp',
      );
      expect(imageMimeType(Uint8List.fromList('<svg'.codeUnits)), isNull);
    });
  });

  group('Reference tool', () {
    test('upload is one Undo step and selects the image', () {
      final (editor, _) = withImage();
      final image = editor.selectedImage!;
      expect(editor.referenceSelected, isTrue);
      expect(editor.showsReference, isTrue);
      expect(editor.undoLabel, 'Add reference image');
      // Centred in the 800×600 view; a wide picture fills 80% of its width.
      expect(editor.camera.toScreen(image.centre), const Offset(400, 300));
      expect(image.worldWidth * pixelsPerMetre, closeTo(640, 1e-9));
      editor.undo();
      expect(editor.selectedImage, isNull);
      expect(editor.referenceSelected, isFalse);
    });

    test('two clicks draw the line, a distance scales the image', () {
      final (editor, input) = withImage();
      final image = editor.selectedImage!;
      final camera = editor.camera;
      final a = image.toWorld(const Vec(100, 100));
      final b = image.toWorld(const Vec(300, 100));
      click(input, at(a, camera));
      expect(editor.referenceLineStart, isNotNull);
      expect(identical(editor.selectedImage, image), isTrue);
      input.hover(at(b, camera));
      expect(editor.preview, isA<ReferenceLinePreview>());
      click(input, at(b, camera));
      final lined = editor.selectedImage!;
      expect(lined.hasLine, isTrue);
      expect(editor.undoLabel, 'Reference line');

      expect(editor.calibrateReference(image.id, 0), isNotNull);
      expect(editor.calibrateReference(image.id, 12), isNull);
      final scaled = editor.selectedImage!;
      expect(scaled.lineLength, closeTo(12, 1e-9));
      expect(scaled.isCalibrated, isTrue);
      expect(scaled.toWorld(scaled.lineStart!).distanceTo(a), lessThan(1e-6));
      editor.undo();
      expect(editor.selectedImage, same(lined));
    });

    test('a reference line can be dragged out in one press', () {
      final (editor, input) = withImage();
      final image = editor.selectedImage!;
      final from = at(image.toWorld(const Vec(100, 100)), editor.camera);
      final to = at(image.toWorld(const Vec(300, 100)), editor.camera);
      input.press(from, shift: false);
      input.move(from + (to - from) / 2);
      expect(editor.referenceLineStart, isNotNull);
      expect(editor.preview, isA<ReferenceLinePreview>());
      input.move(to);
      input.release(to);
      final lined = editor.selectedImage!;
      expect(lined.lineStart!.distanceTo(const Vec(100, 100)), lessThan(1e-6));
      expect(lined.lineEnd!.distanceTo(const Vec(300, 100)), lessThan(1e-6));
      expect(editor.referenceLineStart, isNull);
      expect(editor.undoLabel, 'Reference line');
    });

    test('clicks off the image are refused; Esc forgets the first end', () {
      final (editor, input) = withImage();
      click(input, const Offset(5, 5));
      expect(editor.notice, contains('Click on an unlocked reference image'));
      final image = editor.selectedImage!;
      click(input, at(image.centre, editor.camera));
      expect(editor.referenceLineStart, isNotNull);
      editor.escape();
      expect(editor.referenceLineStart, isNull);
      expect(editor.selectedImage!.hasLine, isFalse);
    });

    test('the tool does nothing until an image is uploaded', () {
      final editor = EditorController()..setViewportSize(const Size(800, 600));
      addTearDown(editor.dispose);
      final input = CanvasInput(editor);
      editor.selectTool(Tool.reference);
      final before = editor.document;
      click(input, const Offset(400, 300));
      expect(identical(editor.document, before), isTrue);
      expect(editor.notice, contains('Add a reference image'));
    });
  });

  group('Select on the reference image', () {
    test('dragging the inside moves it and keeps the calibration', () {
      final (editor, input) = withImage();
      final image = editor.selectedImage!
          .withLine(const Vec(0, 0), const Vec(400, 0))
          .calibratedTo(20);
      editor.updateReference('setup', image);
      editor.selectTool(Tool.select);
      final from = at(image.centre, editor.camera);
      input.press(from, shift: false);
      input.move(from + const Offset(30, 0));
      expect(editor.preview, isA<ReferencePreview>());
      expect(identical(editor.selectedImage, image), isTrue);
      input.move(from + const Offset(60, 0));
      input.release(from + const Offset(60, 0));
      final moved = editor.selectedImage!;
      expect(moved.topLeft.x - image.topLeft.x, closeTo(2, 1e-9));
      expect(moved.isCalibrated, isTrue);
      expect(editor.undoLabel, 'Move reference image');
    });

    test('dragging a corner scales about the opposite corner', () {
      final (editor, input) = withImage();
      editor.selectTool(Tool.select);
      final image = editor.selectedImage!;
      final corner = at(image.bottomRight, editor.camera);
      drag(input, corner, corner + const Offset(90, 0));
      final scaled = editor.selectedImage!;
      expect(scaled.topLeft, image.topLeft);
      expect(
        scaled.worldWidth / scaled.worldHeight,
        closeTo(image.worldWidth / image.worldHeight, 1e-9),
      );
      expect(scaled.worldWidth, closeTo(image.worldWidth + 3, 1e-9));
      expect(editor.undoLabel, 'Scale reference image');
    });

    test('land drawn over the image is picked before the image', () {
      final (editor, input) = withImage();
      editor.addLayer(LayerKind.property);
      editor.selectTool(Tool.polygon);
      editor.selectFunction(ToolFunction.rectangle);
      final image = editor.document.references.single;
      click(input, at(image.centre - const Vec(1, 1), editor.camera));
      click(input, at(image.centre + const Vec(1, 1), editor.camera));
      editor.selectTool(Tool.select);
      click(input, at(image.centre, editor.camera));
      expect(editor.referenceSelected, isFalse);
      expect(editor.selection, isNotEmpty);
      click(input, at(image.topLeft + const Vec(0.5, 0.5), editor.camera));
      expect(editor.referenceSelected, isTrue);
      expect(editor.selection, isEmpty);
    });

    test('a locked image cannot be picked or moved', () {
      final (editor, input) = withImage();
      final image = editor.selectedImage!;
      editor.updateReference('Lock', image.withLocked(true));
      editor.selectTool(Tool.select);
      editor.selectItem(null);
      final from = at(image.centre, editor.camera);
      drag(input, from, from + const Offset(60, 0));
      expect(editor.document.references.single.topLeft, image.topLeft);
      expect(editor.referenceSelected, isFalse);
    });

    test('Delete removes the selected image; Undo restores it', () {
      final (editor, _) = withImage();
      final image = editor.selectedImage!;
      editor.deleteSelection();
      expect(editor.document.references, isEmpty);
      editor.undo();
      expect(editor.document.referenceById(image.id), same(image));
    });
  });

  test('opacity previews while dragging and saves once on release', () {
    final (editor, _) = withImage();
    final history = editor.undoLabel;
    editor.previewReferenceOpacity(0.2);
    expect(editor.opacityOf(editor.selectedImage!), 0.2);
    expect(editor.selectedImage!.opacity, 0.6);
    expect(editor.undoLabel, history);
    editor.setReferenceOpacity(0.25);
    expect(editor.selectedImage!.opacity, 0.25);
    expect(editor.undoLabel, 'Reference opacity');
    editor.undo();
    expect(editor.selectedImage!.opacity, 0.6);
  });

  test('the image and its calibration are saved and reopened', () {
    final (editor, _) = withImage();
    final image = editor.selectedImage!
        .withLine(const Vec(10, 20), const Vec(210, 20))
        .calibratedTo(7.5)
        .withOpacity(0.4)
        .withLocked(true);
    editor.updateReference('setup', image);
    final reopened = decodeGgnome(
      encodeGgnome(editor.document),
    ).referenceById(image.id)!;
    expect(reopened.bytes, image.bytes);
    expect(reopened.topLeft, image.topLeft);
    expect(reopened.metresPerPixel, image.metresPerPixel);
    expect(reopened.lineStart, image.lineStart);
    expect(reopened.lineEnd, image.lineEnd);
    expect(reopened.knownDistance, 7.5);
    expect(reopened.opacity, 0.4);
    expect(reopened.locked, isTrue);
    expect(documentToJson(editor.document)['schema_version'], schemaVersion);
  });

  test('a file whose reference picture is missing is refused', () {
    final (editor, _) = withImage();
    final json = documentToJson(editor.document);
    expect(
      () => documentFromJson(json, readAsset: (_) => null),
      throwsA(isA<DocumentFormatError>()),
    );
  });

  group('several images', () {
    Uint8List picture() => Uint8List.fromList(png);

    test('each image is added on top, with its own ID and name', () {
      final (editor, _) = withImage();
      final first = editor.selectedImage!;
      editor.addReferenceImage(
        bytes: picture(),
        mimeType: 'image/png',
        pixelWidth: 100,
        pixelHeight: 100,
      );
      final second = editor.selectedImage!;
      expect(editor.document.references.map((i) => i.id), [
        first.id,
        second.id,
      ]);
      expect(first.displayName, 'Image 1');
      expect(second.displayName, 'Image 2');
      // Removing and adding again never reuses a number.
      editor.removeReference(second.id);
      editor.addReferenceImage(
        bytes: picture(),
        mimeType: 'image/png',
        pixelWidth: 100,
        pixelHeight: 100,
      );
      expect(editor.selectedImage!.id, 'image-3');
    });

    test('each image is calibrated from its own line, independently', () {
      final (editor, input) = withImage();
      final a = editor.selectedImage!;
      editor.addReferenceImage(
        bytes: picture(),
        mimeType: 'image/png',
        pixelWidth: 400,
        pixelHeight: 200,
      );
      final b = editor.selectedImage!;
      // Draw a line on the top image (b), which covers a.
      final from = b.toWorld(const Vec(50, 100));
      final to = b.toWorld(const Vec(250, 100));
      click(input, at(from, editor.camera));
      click(input, at(to, editor.camera));
      expect(editor.calibrateReference(b.id, 10), isNull);
      final calibratedB = editor.document.referenceById(b.id)!;
      expect(calibratedB.lineLength, closeTo(10, 1e-9));
      // The other image is untouched.
      expect(editor.document.referenceById(a.id), same(a));

      // Select the lower image and give it a different line and distance.
      editor.selectReference(a.id);
      editor.updateReference(
        'Reference line',
        a.withLine(const Vec(0, 0), const Vec(100, 0)),
      );
      expect(editor.calibrateReference(a.id, 3), isNull);
      final calibratedA = editor.document.referenceById(a.id)!;
      expect(calibratedA.lineLength, closeTo(3, 1e-9));
      expect(
        editor.document.referenceById(b.id)!.metresPerPixel,
        calibratedB.metresPerPixel,
      );
    });

    test(
      'a selected image lower down can take a line through the one above',
      () {
        final (editor, input) = withImage();
        final lower = editor.selectedImage!;
        editor.addReferenceImage(
          bytes: picture(),
          mimeType: 'image/png',
          pixelWidth: 400,
          pixelHeight: 200,
        );
        editor.selectReference(lower.id);
        click(input, at(lower.toWorld(const Vec(50, 50)), editor.camera));
        expect(editor.referenceLineImageId, lower.id);
      },
    );

    test('Select picks the top image; its handles scale only it', () {
      final (editor, input) = withImage();
      final lower = editor.selectedImage!;
      editor.addReferenceImage(
        bytes: picture(),
        mimeType: 'image/png',
        pixelWidth: 100,
        pixelHeight: 100,
      );
      final upper = editor.selectedImage!;
      editor.selectTool(Tool.select);
      editor.selectItem(null);
      click(input, at(upper.centre, editor.camera));
      expect(editor.selectedImage?.id, upper.id);
      final corner = at(upper.bottomRight, editor.camera);
      drag(input, corner, corner + const Offset(30, 30));
      expect(editor.document.referenceById(lower.id), same(lower));
      expect(
        editor.document.referenceById(upper.id)!.worldWidth,
        greaterThan(upper.worldWidth),
      );
    });

    test(
      'images reorder, lock together, and the layer deletes as one step',
      () {
        final (editor, _) = withImage();
        final first = editor.selectedImage!;
        editor.addReferenceImage(
          bytes: picture(),
          mimeType: 'image/png',
          pixelWidth: 100,
          pixelHeight: 100,
        );
        editor.moveReference(first.id, up: true);
        expect(editor.document.references.last.id, first.id);
        editor.setAllReferencesLocked(true);
        expect(editor.document.references.every((i) => i.locked), isTrue);
        expect(editor.referenceBlocker, contains('locked'));
        editor.removeReferenceLayer();
        expect(editor.document.references, isEmpty);
        editor.undo();
        expect(editor.document.references, hasLength(2));
      },
    );

    test('every image, its name and counter survive save and reopen', () {
      final (editor, _) = withImage();
      editor.addReferenceImage(
        bytes: picture(),
        mimeType: 'image/png',
        pixelWidth: 100,
        pixelHeight: 100,
      );
      final named = editor.selectedImage!.withLabel('Survey');
      editor.updateReference('Rename image', named);
      final reopened = decodeGgnome(encodeGgnome(editor.document));
      expect(reopened.references.map((i) => i.displayName), [
        'Image 1',
        'Survey',
      ]);
      expect(reopened.imageCounter, 2);
    });
  });
}
