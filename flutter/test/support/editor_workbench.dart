import 'package:flutter/material.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/presentation/canvas/drawing_canvas.dart';
import 'package:garden_gnome/presentation/panels/operations_panel.dart';
import 'package:garden_gnome/presentation/panels/properties_panel.dart';
import 'package:garden_gnome/presentation/panels/tools_panel.dart';

import 'widget_harness.dart';

/// Tool-to-canvas integration without the full app's storage/navigation setup.
Widget editorWorkbench(EditorController editor) => testApp(
  child: ListenableBuilder(
    listenable: editor,
    builder: (context, _) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 232,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                ToolsBody(editor: editor),
                OperationsBody(editor: editor),
              ],
            ),
          ),
        ),
        Expanded(child: DrawingCanvas(editor: editor)),
        SizedBox(
          width: 264,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: PropertiesBody(editor: editor),
          ),
        ),
      ],
    ),
  ),
);
