import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../application/texture_library.dart';

/// Reads a texture pack: a zip (usually `.ggtextures`) holding
///
///     pack.json                        {"name": "...", "author": "...",
///                                       "feet_per_repeat": 5}
///     textures/<ground>/<picture>      .png, .jpg, .jpeg or .webp
///
/// where the ground folder is wild_grass, lawn, dirt, prepped_soil, loam or
/// crimson_clover. Pictures elsewhere, or in other folders, are counted as
/// ignored. Without pack.json the file name is the pack's name.
TexturePackContents readTexturePack(
  Uint8List bytes, {
  required String fileName,
}) {
  if (bytes.length > _maxBytes) {
    throw const TextureImportError('This pack is larger than 300 MB');
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: true);
  } catch (_) {
    throw const TextureImportError('This is not a texture pack (a zip file)');
  }
  // Packs zipped from a folder often add one top folder; look inside it.
  final names = [
    for (final f in archive.files)
      if (f.isFile) f.name,
  ];
  final prefix = _commonTop(names);

  Map<String, Object?> meta = {};
  final pictures = <({TextureGround ground, String file, Uint8List bytes})>[];
  var ignored = 0;
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = file.name.substring(prefix.length);
    if (name.startsWith('/') || name.split('/').contains('..')) {
      throw const TextureImportError('The pack has unsafe file names');
    }
    if (name == 'pack.json') {
      try {
        meta = jsonDecode(utf8.decode(file.content)) as Map<String, Object?>;
      } catch (_) {
        throw const TextureImportError('pack.json is not readable');
      }
      continue;
    }
    final parts = name.split('/');
    final ground = parts.length == 3 && parts[0] == 'textures'
        ? TextureGround.byFolder(parts[1])
        : null;
    final picture = RegExp(
      r'\.(png|jpe?g|webp)$',
      caseSensitive: false,
    ).hasMatch(name);
    if (ground == null || !picture || parts[2].startsWith('.')) {
      if (!name.split('/').last.startsWith('.')) ignored++;
      continue;
    }
    if (pictures.length >= _maxPictures) {
      throw const TextureImportError('A pack can hold at most 120 pictures');
    }
    pictures.add((
      ground: ground,
      file: parts[2],
      bytes: Uint8List.fromList(file.content),
    ));
  }
  if (pictures.isEmpty) {
    throw const TextureImportError(
      'No pictures found. Put them in textures/<ground>/ folders',
    );
  }
  final feet = meta['feet_per_repeat'];
  final fallbackName = fileName.replaceFirst(RegExp(r'\.[^.]*$'), '');
  return TexturePackContents(
    name: (meta['name'] as String?)?.trim().isNotEmpty == true
        ? (meta['name'] as String).trim()
        : fallbackName,
    author: meta['author'] as String?,
    feetPerRepeat: feet is num && feet > 0 && feet <= 50
        ? feet.toDouble()
        : TextureLibrary.feetPerRepeat,
    pictures: pictures,
    ignored: ignored,
  );
}

const _maxBytes = 300 * 1024 * 1024;
const _maxPictures = 120;

/// 'name/' when every entry sits in one top folder that is not 'textures'.
String _commonTop(List<String> names) {
  if (names.isEmpty) return '';
  final first = names.first.split('/');
  if (first.length < 2 || first[0] == 'textures') return '';
  final top = '${first[0]}/';
  return names.every((n) => n.startsWith(top)) ? top : '';
}
