import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../application/document_storage.dart';
import '../domain/document.dart';
import '../domain/reference_image.dart';
import 'document_json.dart';

export '../application/document_storage.dart' show DocumentFormatError;
export 'document_json.dart'
    show
        documentFromJson,
        documentToJson,
        formatName,
        oldestSchemaVersion,
        schemaVersion;

const String documentEntry = 'document.json';
const int _maxCompressedBytes = 100 * 1024 * 1024;
const int _maxDocumentBytes = 16 * 1024 * 1024;

class GgnomeCodec implements DocumentCodec {
  const GgnomeCodec();

  @override
  Uint8List encode(GardenDocument document) => encodeGgnome(document);

  @override
  GardenDocument decode(Uint8List bytes) => decodeGgnome(bytes);
}

/// Packs a drawing into a portable .ggnome file (a ZIP with document.json).
Uint8List encodeGgnome(GardenDocument document) {
  final json = utf8.encode(jsonEncode(documentToJson(document)));
  final archive = Archive()..add(ArchiveFile.bytes(documentEntry, json));
  for (final image in document.references) {
    archive.add(
      ArchiveFile.bytes(
        referenceAssetEntry(image.id, image.mimeType),
        image.bytes,
      ),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Reads a .ggnome file, checking it completely before returning it.
GardenDocument decodeGgnome(Uint8List bytes) {
  if (bytes.length > _maxCompressedBytes) {
    throw const DocumentFormatError('This file is too large to open');
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: true);
  } catch (_) {
    throw const DocumentFormatError('This is not a Garden Gnome file');
  }
  final names = <String>{};
  final files = <String, ArchiveFile>{};
  ArchiveFile? entry;
  for (final file in archive.files) {
    final name = file.name;
    if (!names.add(name)) {
      throw const DocumentFormatError('The file has duplicate entries');
    }
    if (name.startsWith('/') || name.split('/').contains('..')) {
      throw const DocumentFormatError('The file has unsafe entries');
    }
    if (name == documentEntry) entry = file;
    files[name] = file;
  }
  if (entry == null) {
    throw const DocumentFormatError('The file has no drawing in it');
  }
  if (entry.size > _maxDocumentBytes) {
    throw const DocumentFormatError('The drawing inside the file is too large');
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(entry.readBytes()!));
  } catch (_) {
    throw const DocumentFormatError('The drawing inside the file is damaged');
  }
  return documentFromJson(
    json,
    readAsset: (name) {
      final file = files[name];
      if (file == null) return null;
      if (file.size > maxReferenceBytes) {
        throw const DocumentFormatError('The reference image is too large');
      }
      try {
        return file.readBytes();
      } catch (_) {
        throw const DocumentFormatError(
          'The reference image in this file is damaged',
        );
      }
    },
  );
}
