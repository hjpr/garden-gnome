import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/storage_error.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/grow/garden_record.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/units.dart';
import 'package:garden_gnome/persistence/drawing_library.dart'
    show BrowserDrawingLibrary;
import 'package:garden_gnome/persistence/garden_record_codec.dart';
import 'package:garden_gnome/persistence/garden_record_store.dart';
import 'package:garden_gnome/persistence/workspace_store.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BlockedFactory extends Fake implements IdbFactory {
  @override
  Future<Database> open(
    String dbName, {
    int? version,
    OnUpgradeNeededFunction? onUpgradeNeeded,
    OnBlockedFunction? onBlocked,
  }) async => throw StateError('Backend unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('preferences adapters', () {
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    const recordKey = 'flutter.garden_gnome.garden_record';
    const workspaceKey = 'flutter.garden_gnome.workspace.drawing';
    late Map<String, Object> backend;
    late bool readFails;
    late bool writeFails;
    late bool writeThrows;

    setUp(() {
      SharedPreferences.resetStatic();
      backend = {};
      readFails = writeFails = writeThrows = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getAll') {
              if (readFails) throw PlatformException(code: 'unavailable');
              return backend;
            }
            if (call.method == 'setString') {
              if (writeThrows) throw PlatformException(code: 'quota');
              if (writeFails) return false;
              final args = call.arguments as Map;
              backend[args['key'] as String] = args['value'] as String;
              return true;
            }
            throw StateError(
              'Unexpected preferences operation: ${call.method}',
            );
          });
    });

    tearDown(() {
      SharedPreferences.resetStatic();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    for (final throwsInstead in [false, true]) {
      test(
        'garden writes report ${throwsInstead ? 'thrown' : 'false'} failures as StorageError',
        () async {
          final before = encodeGardenRecord(GardenRecord());
          backend[recordKey] = before;
          writeFails = !throwsInstead;
          writeThrows = throwsInstead;
          await expectLater(
            BrowserGardenRecordStore().save(GardenRecord(counter: 7)),
            throwsA(isA<StorageError>()),
          );
          expect(backend[recordKey], before);
        },
      );

      test(
        'workspace writes report ${throwsInstead ? 'thrown' : 'false'} failures as StorageError',
        () async {
          backend[workspaceKey] = 'old workspace';
          writeFails = !throwsInstead;
          writeThrows = throwsInstead;
          await expectLater(
            WorkspaceStore().save(
              'drawing',
              const WorkspaceSettings(),
              const Camera(),
              CounterLedger(),
            ),
            throwsA(isA<StorageError>()),
          );
          expect(backend[workspaceKey], 'old workspace');
        },
      );
    }

    test('garden and workspace reads normalize backend failures', () async {
      readFails = true;
      await expectLater(
        BrowserGardenRecordStore().load(),
        throwsA(isA<StorageError>()),
      );
      await expectLater(
        WorkspaceStore().load('drawing'),
        throwsA(isA<StorageError>()),
      );
      await expectLater(
        WorkspaceStore().counters('drawing'),
        throwsA(isA<StorageError>()),
      );
    });

    test(
      'unreadable garden records remain format errors and retain their bytes',
      () async {
        final json = jsonDecode(encodeGardenRecord(GardenRecord())) as Map;
        json['version'] = 99;
        final raw = jsonEncode(json);
        backend[recordKey] = raw;
        await expectLater(
          BrowserGardenRecordStore().load(),
          throwsA(isA<GardenRecordFormatError>()),
        );
        expect(backend[recordKey], raw);
      },
    );

    test('garden records are actually written and read back', () async {
      final store = BrowserGardenRecordStore();
      await store.save(GardenRecord(counter: 7));
      SharedPreferences.resetStatic();
      expect((await store.load()).counter, 7);
      expect(backend.keys, [recordKey]);
    });

    test('workspace settings, camera and counter floors round-trip', () async {
      final store = WorkspaceStore();
      final ledger = CounterLedger()..names[LayerKind.property] = 5;
      ledger.features = 8;
      const settings = WorkspaceSettings(
        units: Units.metres,
        viewMode: ViewMode.render,
      );
      await store.save('drawing', settings, const Camera(height: 42), ledger);
      SharedPreferences.resetStatic();
      final restored = await store.load('drawing');
      expect(restored!.$1.units, Units.metres);
      expect(restored.$1.viewMode, ViewMode.render);
      expect(restored.$2.height, 42);
      final counters = await store.counters('drawing');
      expect(counters.names[LayerKind.property], 5);
      expect(counters.features, 8);
      expect(backend.keys, [workspaceKey]);
    });

    test(
      'missing and malformed optional workspace records keep their fallback',
      () async {
        final store = WorkspaceStore();
        expect(await store.load('drawing'), isNull);
        backend[workspaceKey] = 'damaged';
        SharedPreferences.resetStatic();
        expect(await store.load('drawing'), isNull);
        expect((await store.counters('drawing')).names, isEmpty);
        expect(backend[workspaceKey], 'damaged');
      },
    );
  });

  group('drawing adapter', () {
    test('list, save, open and delete normalize backend failures', () async {
      final library = BrowserDrawingLibrary(factory: _BlockedFactory());
      await expectLater(library.list(), throwsA(isA<StorageError>()));
      await expectLater(
        library.save('id', 'Title', GardenDocument(id: 'id')),
        throwsA(isA<StorageError>()),
      );
      await expectLater(library.open('id'), throwsA(isA<StorageError>()));
      await expectLater(library.delete('id'), throwsA(isA<StorageError>()));
    });

    test(
      'save, list, reopen and deletion work with isolated memory IndexedDB',
      () async {
        final factory = newIdbFactoryMemory();
        final library = BrowserDrawingLibrary(factory: factory);
        final document = GardenDocument(id: 'id');
        await library.save(document.id, 'Orchard', document);
        expect((await library.list()).single.title, 'Orchard');
        expect((await library.open(document.id)).id, document.id);
        await library.delete(document.id);
        expect(await library.list(), isEmpty);
        await expectLater(
          library.open(document.id),
          throwsA(isA<StorageError>()),
        );
      },
    );

    test(
      'damaged stored drawing bytes stay format errors, not storage failures',
      () async {
        final factory = newIdbFactoryMemory();
        final library = BrowserDrawingLibrary(factory: factory);
        await library.save('id', 'Orchard', GardenDocument(id: 'id'));
        final db = await factory.open('garden_gnome');
        addTearDown(db.close);
        final txn = db.transaction('drawings', idbModeReadWrite);
        await txn.objectStore('drawings').put({
          'data': Uint8List.fromList([1, 2, 3]),
        }, 'id');
        await txn.completed;
        await expectLater(
          library.open('id'),
          throwsA(isA<DocumentFormatError>()),
        );
      },
    );
  });
}
