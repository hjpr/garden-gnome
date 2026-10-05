import 'dart:ui' as ui;
import 'package:flutter/services.dart';

class MemoryRenderBundle extends CachingAssetBundle {
  MemoryRenderBundle(this.files);
  final Map<String, ByteData> files;
  final List<String> requested = [];

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    return files[key] ?? (throw StateError('Missing $key'));
  }
}

Future<ByteData> png(int width, int height) =>
    solidPng(width, height, const ui.Color(0xff804020));

Future<ByteData> solidPng(int width, int height, ui.Color colour) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(colour, ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  picture.dispose();
  return bytes;
}
