import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/texture_library.dart';
import 'package:garden_gnome/presentation/panels/preferences_panel.dart';
import 'package:garden_gnome/presentation/panels/textures_panel.dart';

import '../support/render_fixtures.dart';
import '../support/texture_fixtures.dart';
import '../support/widget_harness.dart';

void main() {
  late Uint8List pic;
  setUpAll(() async {
    final data = await solidPng(8, 8, const ui.Color(0xff806040));
    pic = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  });

  Future<(TextureLibrary, List<String>)> pump(
    WidgetTester tester, {
    Future<({String name, Uint8List bytes})?> Function()? pickPack,
  }) async {
    await setTestViewport(tester, size: const Size(900, 900));
    final library = memoryLibrary(picture: pic);
    final notices = <String>[];
    await tester.pumpWidget(
      testApp(
        child: SingleChildScrollView(
          child: TexturesPanel(
            library: library,
            onNotice: (m, {error = false}) => notices.add(m),
            pickPictures: () async => [(name: 'mine.png', bytes: pic)],
            pickPack: pickPack,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (library, notices);
  }

  testWidgets('shows a ground\'s textures, ticks them, and resets', (
    tester,
  ) async {
    final (library, notices) = await pump(tester);
    expect(find.text('Wild grass'), findsOneWidget);
    expect(find.text('a 1'), findsOneWidget);
    expect(find.text('b 1'), findsOneWidget);
    expect(find.text('Built-in'), findsNWidgets(4));
    // The blend order is shown on the ticked ones.
    for (final n in ['1', '2', '3']) {
      expect(find.text(n), findsOneWidget);
    }
    await tester.tap(find.text('b 1'));
    await tester.pumpAndSettle();
    expect(notices.last, contains('At most 3'));
    await tester.tap(find.text('a 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('b 1'));
    await tester.pumpAndSettle();
    expect(library.selected(TextureGround.wildGrass).last, contains('b-1'));
    await tester.tap(find.byTooltip('Back to the built-in textures'));
    await tester.pumpAndSettle();
    expect(library.isDefault(TextureGround.wildGrass), isTrue);
  });

  testWidgets('switching ground lists that ground; Add picture adds there', (
    tester,
  ) async {
    final (library, notices) = await pump(tester);
    await tester.tap(find.text('Wild grass'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prepared soil').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add picture'));
    await tester.pumpAndSettle();
    expect(notices.last, 'Added mine');
    expect(find.text('Your picture'), findsOneWidget);
    expect(library.entries(TextureGround.preppedSoil), hasLength(5));
    expect(library.entries(TextureGround.wildGrass), hasLength(4));
    await tester.tap(find.byTooltip('Remove mine'));
    await tester.pumpAndSettle();
    expect(find.text('Your picture'), findsNothing);
  });

  testWidgets('installs and removes a pack', (tester) async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes(
          'pack.json',
          utf8.encode(jsonEncode({'name': 'Autumn'})),
        ),
      )
      ..addFile(ArchiveFile.bytes('textures/wild_grass/gold.png', pic));
    final zip = ZipEncoder().encodeBytes(archive);
    final (library, notices) = await pump(
      tester,
      pickPack: () async => (name: 'autumn.ggtextures', bytes: zip),
    );
    expect(find.text('No packs installed.'), findsOneWidget);
    await tester.tap(find.text('Install pack'));
    await tester.pumpAndSettle();
    expect(notices.last, startsWith('Installed Autumn'));
    expect(find.text('gold'), findsOneWidget);
    expect(find.text('Autumn'), findsWidgets);
    await tester.tap(find.byTooltip('Remove Autumn'));
    await tester.pumpAndSettle();
    expect(find.text('gold'), findsNothing);
    expect(library.packs, isEmpty);
  });

  testWidgets('Preferences has a Textures category', (tester) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    final library = memoryLibrary(picture: pic);
    await tester.pumpWidget(
      editorPanel(
        editor: editor,
        width: 680,
        height: 520,
        scrollable: false,
        builder: (context) =>
            PreferencesBody(editor: editor, textures: library),
      ),
    );
    await tester.tap(find.text('Textures'));
    await tester.pumpAndSettle();
    expect(find.text('TEXTURE PACKS'), findsOneWidget);
    expect(find.text('Install pack'), findsOneWidget);
  });
}
