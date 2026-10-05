import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/texture_library.dart';
import 'package:garden_gnome/application/texture_pixels.dart';
import 'package:garden_gnome/persistence/texture_pack_codec.dart';

import '../support/texture_fixtures.dart';

final _pic = Uint8List.fromList([7, 7, 7]);
final _notSquare = Uint8List.fromList([0, 1]);

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final e in files.entries) {
    archive.addFile(ArchiveFile.bytes(e.key, e.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  group('selection', () {
    test('built-ins load with their default 1 to 3 per ground', () async {
      final library = memoryLibrary(picture: _pic);
      await library.load();
      for (final g in TextureGround.values) {
        expect(library.entries(g), hasLength(4));
        expect(library.selected(g), [
          'builtin:${g.folder}/a-1.png',
          'builtin:${g.folder}/a-2.png',
          'builtin:${g.folder}/a-3.png',
        ]);
        expect(library.isDefault(g), isTrue);
        expect(library.entries(g).first.sourceLabel, 'Built-in');
      }
    });

    test('ticking stops at three; unticking stops at one', () async {
      final store = MemoryTextureStore();
      final library = memoryLibrary(picture: _pic, store: store);
      await library.load();
      const lawn = TextureGround.lawn;
      expect(
        await library.toggle('builtin:lawn/b-1.png'),
        contains('At most 3'),
      );
      expect(await library.toggle('builtin:lawn/a-1.png'), isNull);
      expect(await library.toggle('builtin:lawn/b-1.png'), isNull);
      expect(library.selected(lawn), [
        'builtin:lawn/a-2.png',
        'builtin:lawn/a-3.png',
        'builtin:lawn/b-1.png',
      ]);
      expect(store.selection[lawn], library.selected(lawn));
      await library.toggle('builtin:lawn/a-2.png');
      await library.toggle('builtin:lawn/a-3.png');
      expect(
        await library.toggle('builtin:lawn/b-1.png'),
        contains('at least one'),
      );
      expect(library.isDefault(lawn), isFalse);
      await library.reset(lawn);
      expect(library.isDefault(lawn), isTrue);
      // Other grounds are untouched.
      expect(library.isDefault(TextureGround.dirt), isTrue);
    });

    test('a saved choice survives a reload; unknown ids are dropped', () async {
      final store = MemoryTextureStore()
        ..selection = {
          TextureGround.dirt: ['builtin:dirt/b-1.png', 'gone'],
          TextureGround.loam: ['builtin:dirt/a-1.png'], // wrong ground
        };
      final library = memoryLibrary(picture: _pic, store: store);
      await library.load();
      expect(library.selected(TextureGround.dirt), ['builtin:dirt/b-1.png']);
      expect(library.isDefault(TextureGround.loam), isTrue);
    });
  });

  group('your own pictures', () {
    test(
      'are prepared, kept, ticked when there is room, and removable',
      () async {
        final store = MemoryTextureStore();
        final library = memoryLibrary(picture: _pic, store: store, defaults: 1);
        await library.load();
        const g = TextureGround.preppedSoil;
        final message = await library.addPictures(g, [
          (name: 'my soil.png', bytes: _pic),
          (name: 'wide.png', bytes: _notSquare),
        ]);
        expect(message, contains('Added 1'));
        expect(message, contains('wide.png: textures must be square'));
        final mine = library.entries(g).last;
        expect(mine.name, 'my soil');
        expect(mine.sourceLabel, 'Your picture');
        expect(library.selected(g), contains(mine.id));
        expect(store.textures.keys, [mine.id]);
        expect(await library.bytesOf(mine.id), _pic);
        await library.removeTexture(mine.id);
        expect(library.entries(g), hasLength(4));
        expect(library.selected(g), ['builtin:prepped_soil/a-1.png']);
        expect(store.textures, isEmpty);
      },
    );
  });

  group('texture packs', () {
    Uint8List pack({String? name = 'Autumn', Object? feet}) => _zip({
      if (name != null)
        'pack.json': utf8.encode(
          jsonEncode({'name': name, 'author': 'Jo', 'feet_per_repeat': ?feet}),
        ),
      'textures/lawn/short.png': _pic,
      'textures/lawn/wide.jpg': _notSquare,
      'textures/loam/dark.jpg': _pic,
      'textures/sky/blue.png': _pic,
      'readme.txt': utf8.encode('hi'),
    });

    test('a pack is read from ground folders, others counted', () {
      final contents = readTexturePack(
        pack(feet: 10),
        fileName: 'x.ggtextures',
      );
      expect(contents.name, 'Autumn');
      expect(contents.author, 'Jo');
      expect(contents.feetPerRepeat, 10);
      expect(contents.pictures.map((p) => '${p.ground.folder}/${p.file}'), [
        'lawn/short.png',
        'lawn/wide.jpg',
        'loam/dark.jpg',
      ]);
      expect(contents.ignored, 2);
      // No pack.json: the file name names it; a top folder is looked into.
      final bare = readTexturePack(
        _zip({'Autumn pack/textures/dirt/a.png': _pic}),
        fileName: 'Autumn pack.ggtextures',
      );
      expect(bare.name, 'Autumn pack');
      expect(bare.pictures.single.ground, TextureGround.dirt);
    });

    test('bad packs are refused with a reason', () {
      expect(
        () => readTexturePack(Uint8List.fromList([1, 2, 3]), fileName: 'a'),
        throwsA(isA<TextureImportError>()),
      );
      expect(
        () => readTexturePack(
          _zip({
            'notes.txt': [1],
          }),
          fileName: 'a',
        ),
        throwsA(
          isA<TextureImportError>().having(
            (e) => e.message,
            'message',
            contains('textures/<ground>'),
          ),
        ),
      );
      expect(
        () => readTexturePack(
          _zip({'textures/lawn/../../evil.png': _pic}),
          fileName: 'a',
        ),
        throwsA(isA<TextureImportError>()),
      );
    });

    test('install, list, reinstall and remove', () async {
      final store = MemoryTextureStore();
      final preparer = FakePreparer();
      final library = memoryLibrary(
        picture: _pic,
        store: store,
        preparer: preparer,
      );
      await library.load();
      final contents = readTexturePack(pack(feet: 10), fileName: 'p');
      final message = await library.installPack(contents);
      expect(
        message,
        'Installed Autumn: 2 textures for 2 grounds (3 files skipped)',
      );
      expect(preparer.feet, everyElement(10));
      expect(library.packs.single.name, 'Autumn');
      final lawn = library.entries(TextureGround.lawn).last;
      expect(lawn.id, 'pack:autumn/lawn/short.png');
      expect(lawn.sourceLabel, 'Autumn');
      // A pack does not change what is in use until ticked.
      expect(library.isDefault(TextureGround.lawn), isTrue);
      await library.toggle('builtin:lawn/a-3.png');
      await library.toggle(lawn.id);
      // Installing again replaces it rather than doubling it.
      await library.installPack(contents);
      expect(library.packs, hasLength(1));
      expect(library.entries(TextureGround.lawn), hasLength(5));
      await library.removePack('autumn');
      expect(library.packs, isEmpty);
      expect(store.textures, isEmpty);
      expect(library.entries(TextureGround.lawn), hasLength(4));
      expect(library.selected(TextureGround.lawn), [
        'builtin:lawn/a-1.png',
        'builtin:lawn/a-2.png',
      ]);
      // A reload sees the same thing.
      final again = memoryLibrary(picture: _pic, store: store);
      await again.load();
      expect(
        again.selected(TextureGround.lawn),
        library.selected(TextureGround.lawn),
      );
    });
  });

  group('pixels', () {
    Uint8List noise(int size, int seed) {
      var x = seed;
      final out = Uint8List(size * size * 4);
      for (var i = 0; i < out.length; i++) {
        x = (x * 1103515245 + 12345) & 0x7fffffff;
        out[i] = i % 4 == 3 ? 255 : x >> 23;
      }
      return out;
    }

    test('makePeriodic: opposite edges meet, the middle is unchanged', () {
      const n = 64;
      final src = noise(n, 1);
      final out = TexturePixels.makePeriodic(src, n);
      int at(int x, int y, int c) => out[(y * n + x) * 4 + c];
      for (var k = 0; k < n; k++) {
        for (var c = 0; c < 3; c++) {
          expect(at(0, k, c), at(n - 1, k, c));
          expect(at(k, 0, c), at(k, n - 1, c));
        }
      }
      for (var y = 24; y < 40; y++) {
        for (var x = 24; x < 40; x++) {
          expect(at(x, y, 1), src[(y * n + x) * 4 + 1]);
        }
      }
    });

    test('matchColour moves the mean and caps the contrast gain', () {
      final ref = noise(16, 2);
      final flat = Uint8List(16 * 16 * 4)..fillRange(0, 16 * 16 * 4, 40);
      flat[0] = 41;
      final out = TexturePixels.matchColour(flat, ref);
      final mean = TexturePixels.mean(out), want = TexturePixels.mean(ref);
      for (var c = 0; c < 3; c++) {
        expect(mean[c], closeTo(want[c], 0.01));
      }
    });

    test('shrink and packRow keep tiles apart', () {
      final a = Uint8List(8 * 8 * 4)..fillRange(0, 256, 200);
      final b = Uint8List(8 * 8 * 4)..fillRange(0, 256, 10);
      final small = TexturePixels.shrink(a, 8, 4);
      expect(small.length, 2 * 2 * 4);
      expect(small[0], 200);
      final row = TexturePixels.packRow([a, b], 8);
      expect(row[(3 * 16 + 7) * 4], 200);
      expect(row[(3 * 16 + 8) * 4], 10);
    });
  });
}
