import 'dart:async';

import 'package:flutter/material.dart';

import 'application/app_tools.dart';
import 'application/document_session.dart';
import 'application/farm.dart';
import 'application/garden_controller.dart';
import 'persistence/crop_catalog_loader.dart';
import 'persistence/document_codec.dart';
import 'persistence/drawing_library.dart';
import 'persistence/garden_record_store.dart';
import 'persistence/workspace_store.dart';
import 'presentation/app_shell.dart';
import 'presentation/theme.dart';

void main() {
  // The catalog and garden record are read before runApp, which needs
  // the asset bundle and plugins ready.
  WidgetsFlutterBinding.ensureInitialized();
  final session = DocumentSession(
    library: BrowserDrawingLibrary(),
    workspace: WorkspaceStore(),
    codec: const GgnomeCodec(),
    lastFarm: LastFarmPreference(),
  );
  // One toast stack for every tool. The growing tools work on the farm
  // open in Build.
  final garden = GardenController(
    store: BrowserGardenRecordStore(),
    toasts: session.toasts,
    farm: SessionFarm(session),
  );
  // The last farm opens before the garden loads, so plantings from the
  // old shared record move into it rather than a blank farm.
  unawaited(() async {
    await session.reopenLastFarm();
    await garden.load(catalog: loadBundledCatalog);
  }());
  runApp(
    GardenGnomeApp(session: session, garden: garden, navigator: AppNavigator()),
  );
}

class GardenGnomeApp extends StatelessWidget {
  const GardenGnomeApp({
    super.key,
    required this.session,
    required this.garden,
    required this.navigator,
  });

  final DocumentSession session;
  final GardenController garden;
  final AppNavigator navigator;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Garden Gnome',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: AppShell(navigator: navigator, session: session, garden: garden),
  );
}
