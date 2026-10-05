import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/document_session.dart';
import 'package:garden_gnome/application/farm_files.dart';
import 'package:garden_gnome/persistence/document_codec.dart';
import 'package:garden_gnome/persistence/drawing_library.dart';
import 'package:garden_gnome/persistence/workspace_store.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Ref implements FarmFileRef {
  _Ref(this.name);

  @override
  final String name;
}

/// Files on disk, held in memory. [needsClick] plays a browser that wants
/// a click before re-reading a remembered file.
class _FakeFiles implements FarmFiles {
  final disk = <String, Uint8List>{};
  _Ref? remembered;
  String? nextSaveName;
  bool needsClick = false;

  @override
  bool get savesInPlace => true;

  @override
  bool get hasBrowserLibrary => true;

  @override
  Future<OpenedFarmFile?> pickToOpen() async => null;

  @override
  Future<FarmFileRef?> pickToSave(String suggestedName, Uint8List bytes) async {
    final name = nextSaveName;
    if (name == null) return null;
    final ref = _Ref(name);
    await write(ref, bytes);
    return ref;
  }

  @override
  Future<void> write(FarmFileRef ref, Uint8List bytes) async =>
      disk[ref.name] = bytes;

  @override
  Future<void> remember(FarmFileRef? ref) async => remembered = ref as _Ref?;

  @override
  Future<String?> rememberedName() async => remembered?.name;

  @override
  Future<Reopened> reopen({bool ask = false}) async {
    final ref = remembered;
    if (ref == null || !disk.containsKey(ref.name)) {
      return const NothingToReopen();
    }
    if (needsClick && !ask) return ReopenNeedsPermission(ref.name);
    return ReopenedFile(OpenedFarmFile(disk[ref.name]!, ref.name, ref));
  }

  @override
  Future<void> exportCopy(String name, Uint8List bytes) async {}
}

void main() {
  late _FakeFiles files;
  late BrowserDrawingLibrary library;

  DocumentSession newSession() => DocumentSession(
    library: library,
    workspace: WorkspaceStore(),
    codec: const GgnomeCodec(),
    lastFarm: LastFarmPreference(),
    files: files,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    files = _FakeFiles();
    library = BrowserDrawingLibrary(factory: newIdbFactoryMemory());
  });

  test(
    'Save as picks a file; Save writes back; the file reopens at start-up',
    () async {
      final session = newSession();
      expect(session.savesToFiles, isTrue);
      files.nextSaveName = 'Hill farm.ggnome';
      expect(await session.saveAsFile(), isA<Succeeded>());
      expect(files.disk, contains('Hill farm.ggnome'));
      expect(session.editor.title, 'Hill farm');
      expect(session.editor.fileRef?.name, 'Hill farm.ggnome');
      expect(session.hasUnsavedWork, isFalse);

      session.editor.renameDrawing('Hill farm 2');
      final before = files.disk['Hill farm.ggnome'];
      expect(await session.save(), isA<Succeeded>());
      expect(files.disk['Hill farm.ggnome'], isNot(same(before)));
      expect(files.disk, hasLength(1), reason: 'written in place');

      final next = newSession();
      await next.reopenLastFarm();
      expect(next.editor.fileRef?.name, 'Hill farm.ggnome');
      expect(next.editor.document.id, session.editor.document.id);
      expect(next.hasUnsavedWork, isFalse);
    },
  );

  test('a cancelled save picker changes nothing', () async {
    final session = newSession();
    expect(await session.saveAsFile(), isNull);
    expect(files.disk, isEmpty);
    expect(session.editor.fileRef, isNull);
  });

  test('a missing file leaves the empty farm', () async {
    files.remembered = _Ref('Gone.ggnome');
    final session = newSession();
    final blank = session.editor.document.id;
    await session.reopenLastFarm();
    expect(session.editor.document.id, blank);
    expect(session.reopenWaiting, isNull);
  });

  test('when the browser wants a click, the session waits and reopens on '
      'request; Not now forgets the file', () async {
    final first = newSession();
    files.nextSaveName = 'Farm.ggnome';
    await first.saveAsFile();
    files.needsClick = true;

    final second = newSession();
    await second.reopenLastFarm();
    expect(second.reopenWaiting, 'Farm.ggnome');
    expect(await second.reopenFile(), isA<Succeeded>());
    expect(second.reopenWaiting, isNull);
    expect(second.editor.fileRef?.name, 'Farm.ggnome');

    final third = newSession();
    await third.reopenLastFarm();
    await third.skipReopen();
    expect(third.reopenWaiting, isNull);
    expect(files.remembered, isNull);
  });

  test('New forgets the remembered file; the browser library wins when '
      'saved there last', () async {
    final session = newSession();
    files.nextSaveName = 'Farm.ggnome';
    await session.saveAsFile();
    await session.newDrawing();
    expect(files.remembered, isNull);

    files.nextSaveName = 'Farm.ggnome';
    await session.saveAsFile();
    expect(await session.saveAs('In browser'), isA<Succeeded>());
    expect(files.remembered, isNull, reason: 'library save is the latest');
  });
}
