import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

Future<bool> saveCopy(
  String name,
  Uint8List bytes, {
  required String mimeType,
  required XTypeGroup type,
}) async {
  await XFile.fromData(bytes, name: name, mimeType: mimeType).saveTo(name);
  return true;
}
