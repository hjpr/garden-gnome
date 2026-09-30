import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/document_session.dart';
import 'package:garden_gnome/application/document_storage.dart';
import 'package:garden_gnome/application/storage_error.dart';
import 'package:garden_gnome/application/toasts.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/units.dart';

class _Library implements DrawingLibrary {
  Object? openError;
  final candidate = GardenDocument(id: 'stored');
  GardenDocument? saved;

  @override
  Future<GardenDocument> open(String id) async {
    if (openError case final error?) throw error;
    return candidate;
  }

  @override
  Future<void> save(String id, String title, GardenDocument document) async {
    saved = document;
  }

  @override
  Future<List<LibraryEntry>> list() async => [];

  @override
  Future<void> delete(String id) async {}
}

class _Workspace implements WorkspaceStorage {
  StorageError? loadError;
  StorageError? counterError;
  StorageError? saveError;
  (WorkspaceSettings, Camera)? restored;
  final ledger = CounterLedger();
  final savedIds = <String>[];

  @override
  Future<(WorkspaceSettings, Camera)?> load(String documentId) async {
    if (loadError case final error?) throw error;
    return restored;
  }

  @override
  Future<CounterLedger> counters(String documentId) async {
    if (counterError case final error?) throw error;
    return ledger;
  }

  @override
  Future<void> save(
    String documentId,
    WorkspaceSettings settings,
    Camera camera,
    CounterLedger ledger,
  ) async {
    if (saveError case final error?) throw error;
    savedIds.add(documentId);
  }
}

class _Codec implements DocumentCodec {
  DocumentFormatError? error;
  final candidate = GardenDocument(id: 'imported');
  final encodedBytes = Uint8List.fromList([1, 2, 3]);
  Uint8List? decodedBytes;
  GardenDocument? encodedDocument;

  @override
  GardenDocument decode(Uint8List bytes) {
    decodedBytes = bytes;
    if (error case final problem?) throw problem;
    return candidate;
  }

  @override
  Uint8List encode(GardenDocument document) {
    encodedDocument = document;
    return encodedBytes;
  }
}

void main() {
  late _Library library;
  late _Workspace workspace;
  late _Codec codec;
  late DocumentSession session;
  final entry = LibraryEntry(
    id: 'stored',
    title: 'Stored drawing',
    savedAt: DateTime(2026),
  );

  setUp(() {
    library = _Library();
    workspace = _Workspace();
    codec = _Codec();
    session = DocumentSession(
      library: library,
      workspace: workspace,
      codec: codec,
    );
  });

  tearDown(() {
    session.editor.dispose();
    session.toasts.dispose();
    session.dispose();
  });

  for (final error in [
    const StorageError('Blocked'),
    const DocumentFormatError('Damaged'),
  ]) {
    test(
      'failed Open ($error) leaves the current editor and edits intact',
      () async {
        session.editor.addLayer(LayerKind.property);
        final editor = session.editor;
        final document = editor.document;
        library.openError = error;
        expect(await session.open(entry), isA<Failed>());
        expect(session.editor, same(editor));
        expect(session.editor.document, same(document));
        expect(session.editor.isDirty, isTrue);
        expect(workspace.savedIds, isEmpty);
      },
    );
  }

  test('failed Import never replaces the current editor', () async {
    session.editor.addLayer(LayerKind.property);
    final editor = session.editor;
    codec.error = const DocumentFormatError('Bad file');
    final result = await session.import(Uint8List(0), 'bad.ggnome');
    expect(
      result,
      isA<Failed>().having((r) => r.message, 'message', 'Bad file'),
    );
    expect(session.editor, same(editor));
    expect(session.editor.isDirty, isTrue);
    expect(workspace.savedIds, isEmpty);
  });

  for (final importing in [false, true]) {
    for (final counters in [false, true]) {
      test(
        '${importing ? 'Import' : 'Open'} keeps the editor when workspace ${counters ? 'counters' : 'load'} fails',
        () async {
          session.editor.addLayer(LayerKind.property);
          final editor = session.editor;
          if (counters) {
            workspace.counterError = const StorageError(
              'Workspace unavailable',
            );
          } else {
            workspace.loadError = const StorageError('Workspace unavailable');
          }
          final result = importing
              ? await session.import(Uint8List(0), 'drawing.ggnome')
              : await session.open(entry);
          expect(result, isA<Failed>());
          expect(session.editor, same(editor));
          expect(session.editor.isDirty, isTrue);
        },
      );
    }
  }

  test(
    'Import and Export use the injected codec and restore the workspace',
    () async {
      final bytes = Uint8List.fromList([4, 5]);
      const settings = WorkspaceSettings(units: Units.metres);
      const camera = Camera(height: 42);
      workspace.restored = (settings, camera);
      workspace.ledger.names[LayerKind.property] = 7;
      expect(await session.import(bytes, 'Orchard.ggnome'), isA<Succeeded>());
      expect(codec.decodedBytes, same(bytes));
      expect(session.editor.document.id, 'imported');
      expect(session.editor.title, 'Orchard');
      expect(session.editor.libraryId, isNull);
      expect(session.editor.settings, same(settings));
      expect(session.editor.camera, same(camera));
      expect(session.editor.ledger.names[LayerKind.property], 7);
      expect(session.editor.isDirty, isFalse);
      expect(session.export(), same(codec.encodedBytes));
      expect(codec.encodedDocument, same(session.editor.document));
    },
  );

  test('a confirmed drawing save survives a workspace write failure', () async {
    session.editor.addLayer(LayerKind.property);
    workspace.saveError = const StorageError('Workspace was not saved');
    expect(await session.save(), isA<Succeeded>());
    expect(library.saved!.layers, hasLength(1));
    expect(session.editor.libraryId, isNotNull);
    expect(session.editor.isDirty, isFalse);
    expect(session.toasts.toasts.single.message, 'Workspace was not saved');
    expect(session.toasts.toasts.single.kind, ToastKind.error);
  });

  test(
    'lifecycle workspace failures are reported rather than unhandled',
    () async {
      workspace.saveError = const StorageError('Workspace was not saved');
      await session.rememberWorkspace();
      expect(session.toasts.toasts.single.kind, ToastKind.error);
      final old = session.editor;
      await session.newDrawing();
      expect(session.editor, isNot(same(old)));
      expect(session.toasts.toasts.single.message, 'Workspace was not saved');
    },
  );
}
