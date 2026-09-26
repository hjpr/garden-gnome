import 'package:flutter/material.dart';

import 'application/document_session.dart';
import 'persistence/drawing_library.dart';
import 'persistence/workspace_store.dart';
import 'presentation/build_screen.dart';
import 'presentation/theme.dart';

void main() {
  runApp(
    GardenGnomeApp(
      session: DocumentSession(
        library: BrowserDrawingLibrary(),
        workspace: WorkspaceStore(),
      ),
    ),
  );
}

class GardenGnomeApp extends StatelessWidget {
  const GardenGnomeApp({super.key, required this.session});

  final DocumentSession session;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Garden Gnome — Build',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: BuildScreen(session: session),
  );
}
