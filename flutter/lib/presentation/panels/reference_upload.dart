import 'package:file_selector/file_selector.dart';

import '../../application/editor_controller.dart';
import '../../domain/reference_image.dart';
import '../canvas/reference_image_cache.dart';

/// Picks a picture, checks it, and adds it on top of the Reference layer.
/// Returns why the picture could not be used, or null when it was added
/// or the picker was cancelled (which changes nothing).
///
/// Used by Properties > Upload image and by Layers > Add layer.
Future<String?> uploadReferenceImage(EditorController editor) async {
  const group = XTypeGroup(
    label: 'Images',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
    mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
  );
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  final document = editor.document;
  try {
    final bytes = await file.readAsBytes();
    final mimeType = imageMimeType(bytes);
    if (bytes.length > maxReferenceBytes) {
      return 'That image is over 20 MB. Choose a smaller one';
    }
    if (mimeType == null) return 'Choose a PNG, JPEG or WebP image';
    final size = await decodeImageSize(bytes);
    if (size == null) return 'That image could not be read';
    if (size.width * size.height > maxReferencePixels) {
      return 'That image is over 40 megapixels. Choose a smaller one';
    }
    if (!identical(editor.document, document)) {
      // The drawing changed while the file loaded (another drawing
      // opened, or an Undo); do not drop the picture into it.
      return 'The drawing changed while loading. Try again';
    }
    editor.addReferenceImage(
      fileName: file.name,
      bytes: bytes,
      mimeType: mimeType,
      pixelWidth: size.width,
      pixelHeight: size.height,
    );
    return null;
  } catch (_) {
    return 'That image could not be read';
  }
}
