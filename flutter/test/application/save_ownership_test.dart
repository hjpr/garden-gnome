import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/document_session.dart';
import 'package:garden_gnome/application/document_storage.dart';
import 'package:garden_gnome/application/storage_error.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/persistence/document_codec.dart';

/// A library whose save waits until the test lets it finish, so edits can
/// be made while a save is in flight.
class _HeldLibrary implements DrawingLibrary {
  final releases = [Completer<void>()];
  Completer<void> get release => releases.first;
  final saved = <(String id, String title, GardenDocument document)>[];
  final stored = <String, GardenDocument>{};

  @override
  Future<void> save(String id, String title, GardenDocument document) async {
    final index = saved.length;
    saved.add((id, title, document));
    await releases[index].future;
    stored[id] = document;
  }

  @override
  Future<List<LibraryEntry>> list() async => const [];

  @override
  Future<GardenDocument> open(String id) async => saved.last.$3;

  @override
  Future<void> delete(String id) async {}
}

class _NoWorkspace implements WorkspaceStorage {
  @override
  Future<(WorkspaceSettings, Camera)?> load(String documentId) async => null;

  @override
  Future<CounterLedger> counters(String documentId) async => CounterLedger();

  @override
  Future<void> save(
    String documentId,
    WorkspaceSettings settings,
    Camera camera,
    CounterLedger ledger,
  ) async {}
}

(DocumentSession, _HeldLibrary) session() {
  final library = _HeldLibrary();
  final s = DocumentSession(
    library: library,
    workspace: _NoWorkspace(),
    codec: const GgnomeCodec(),
  );
  addTearDown(() {
    s.editor.dispose();
    s.toasts.dispose();
    s.dispose();
  });
  return (s, library);
}

void main() {
  test('a queued save continues after the preceding write fails', () async {
    final (s, library) = session();
    s.editor.libraryId = s.editor.document.id;
    library.releases.add(Completer<void>());
    final first = s.save();
    s.editor.addLayer(LayerKind.property);
    final second = s.save();
    await Future<void>.delayed(Duration.zero);
    library.release.completeError(const StorageError('Full'));
    expect(await first, isA<Failed>());
    await Future<void>.delayed(Duration.zero);
    expect(library.saved, hasLength(2));
    library.releases.last.complete();
    expect(await second, isA<Succeeded>());
    expect(s.editor.isDirty, isFalse);
    expect(library.stored[s.editor.libraryId]!.layers, hasLength(1));
  });

  test(
    'a Save as finishing after Import leaves the imported editor alone',
    () async {
      final (s, library) = session();
      s.editor.addLayer(LayerKind.property);
      final saving = s.saveAs('Old copy');
      final imported = GardenDocument(id: 'imported');
      expect(
        await s.import(encodeGgnome(imported), 'Other.ggnome'),
        isA<Succeeded>(),
      );
      final editor = s.editor;
      library.release.complete();
      expect(await saving, isA<Succeeded>());
      expect(s.editor, same(editor));
      expect(s.editor.document.id, 'imported');
      expect(s.editor.title, 'Other');
      expect(s.editor.libraryId, isNull);
      expect(s.editor.isDirty, isFalse);
    },
  );

  test('overlapping saves write their snapshots in invocation order', () async {
    final (s, library) = session();
    s.editor.libraryId = s.editor.document.id;
    library.releases.add(Completer<void>());
    final first = s.save();
    s.editor.addLayer(LayerKind.property);
    final second = s.save();
    await Future<void>.delayed(Duration.zero);
    expect(library.saved, hasLength(1));
    expect(library.saved.first.$3.layers, isEmpty);

    library.release.complete();
    expect(await first, isA<Succeeded>());
    await Future<void>.delayed(Duration.zero);
    expect(library.saved, hasLength(2));
    expect(library.saved.last.$3.layers, hasLength(1));
    expect(s.editor.isDirty, isTrue);
    library.releases.last.complete();
    expect(await second, isA<Succeeded>());
    expect(library.stored[s.editor.libraryId]!.layers, hasLength(1));
    expect(s.editor.isDirty, isFalse);
  });

  test(
    'Save follows a pending Save as identity instead of the old file',
    () async {
      final (s, library) = session();
      s.editor.libraryId = s.editor.document.id;
      final oldId = s.editor.libraryId;
      library.releases.add(Completer<void>());
      final first = s.saveAs('Copy');
      s.editor.addLayer(LayerKind.property);
      final second = s.save();
      library.release.complete();
      expect(await first, isA<Succeeded>());
      await Future<void>.delayed(Duration.zero);
      expect(library.saved.last.$1, library.saved.first.$1);
      expect(library.saved.last.$1, isNot(oldId));
      expect(library.saved.last.$3.id, library.saved.last.$1);
      library.releases.last.complete();
      expect(await second, isA<Succeeded>());
      expect(s.editor.isDirty, isFalse);
    },
  );

  test(
    'overlapping Save as copies leave the last requested identity open',
    () async {
      final (s, library) = session();
      library.releases.add(Completer<void>());
      final first = s.saveAs('First');
      s.editor.addLayer(LayerKind.property);
      final second = s.saveAs('Second');
      s.editor.renameDrawing('Still editing');
      library.release.complete();
      expect(await first, isA<Succeeded>());
      await Future<void>.delayed(Duration.zero);
      library.releases.last.complete();
      expect(await second, isA<Succeeded>());
      expect(library.stored, hasLength(2));
      expect(library.saved.first.$3.layers, isEmpty);
      expect(library.saved.last.$3.layers, hasLength(1));
      expect(s.editor.document.id, library.saved.last.$1);
      expect(s.editor.title, 'Still editing');
      expect(s.editor.isDirty, isTrue);
    },
  );

  test('a failed queued save keeps the last confirmed snapshot', () async {
    final (s, library) = session();
    s.editor.libraryId = s.editor.document.id;
    library.releases.add(Completer<void>());
    final first = s.save();
    s.editor.addLayer(LayerKind.property);
    final second = s.save();
    library.release.complete();
    expect(await first, isA<Succeeded>());
    await Future<void>.delayed(Duration.zero);
    library.releases.last.completeError(const StorageError('Full'));
    expect(await second, isA<Failed>());
    expect(library.stored[s.editor.libraryId]!.layers, isEmpty);
    expect(s.editor.document.layers, hasLength(1));
    expect(s.editor.isDirty, isTrue);

    library.releases.add(Completer<void>()..complete());
    expect(await s.save(), isA<Succeeded>());
    expect(s.editor.isDirty, isFalse);
  });

  test('a failed Save as does not adopt its unconfirmed identity', () async {
    final (s, library) = session();
    final id = s.editor.document.id;
    final saving = s.saveAs('Copy');
    s.editor.addLayer(LayerKind.property);
    await Future<void>.delayed(Duration.zero);
    library.release.completeError(const StorageError('Full'));
    expect(await saving, isA<Failed>());
    expect(s.editor.document.id, id);
    expect(s.editor.libraryId, isNull);
    expect(s.editor.title, 'Copy');
    expect(s.editor.document.layers, hasLength(1));
    expect(s.editor.isDirty, isTrue);
  });

  test('a layer added while Save runs is kept and still unsaved', () async {
    final (s, library) = session();
    s.editor.libraryId = s.editor.document.id;
    final saving = s.save();
    s.editor.addLayer(LayerKind.property);
    final added = s.editor.selectedLayerId!;
    library.release.complete();
    expect(await saving, isA<Succeeded>());
    expect(s.editor.document.layers, contains(added));
    expect(s.editor.isDirty, isTrue, reason: 'the new layer is not saved');
  });

  test(
    'a layer added while Save as runs is kept under the new identity',
    () async {
      final (s, library) = session();
      final saving = s.saveAs('Copy');
      s.editor.addLayer(LayerKind.property);
      final added = s.editor.selectedLayerId!;
      library.release.complete();
      expect(await saving, isA<Succeeded>());
      expect(s.editor.document.id, library.saved.single.$1);
      expect(s.editor.libraryId, library.saved.single.$1);
      expect(s.editor.document.layers, contains(added));
      expect(s.editor.isDirty, isTrue);
    },
  );

  test('a rename while Save runs is kept and still unsaved', () async {
    final (s, library) = session();
    s.editor.libraryId = s.editor.document.id;
    final saving = s.save();
    s.editor.renameDrawing('Renamed meanwhile');
    library.release.complete();
    expect(await saving, isA<Succeeded>());
    expect(s.editor.title, 'Renamed meanwhile');
    expect(s.editor.isDirty, isTrue);
  });

  test('Save as takes the new name at once', () async {
    final (s, library) = session();
    final saving = s.saveAs('  Orchard  ');
    expect(s.editor.title, 'Orchard');
    library.release.complete();
    expect(await saving, isA<Succeeded>());
    expect(s.editor.isDirty, isFalse);
  });

  test('a save finishing after New leaves the new drawing alone', () async {
    final (s, library) = session();
    s.editor.libraryId = s.editor.document.id;
    s.editor.addLayer(LayerKind.property);
    final saving = s.save();
    await s.newDrawing();
    final fresh = s.editor;
    library.release.complete();
    expect(await saving, isA<Succeeded>());
    expect(s.editor, same(fresh));
    expect(s.editor.document.layers, isEmpty);
    expect(s.editor.libraryId, isNull);
  });
}
