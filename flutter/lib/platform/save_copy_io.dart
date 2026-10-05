import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

Future<bool> saveCopy(
  String name,
  Uint8List bytes, {
  required String mimeType,
  required XTypeGroup type,
}) async {
  final where = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [type],
  );
  if (where == null) return false;
  final extension = '.${type.extensions!.first}';
  final path = where.path.endsWith(extension)
      ? where.path
      : '${where.path}$extension';
  await File(path).writeAsBytes(bytes, flush: true);
  return true;
}
