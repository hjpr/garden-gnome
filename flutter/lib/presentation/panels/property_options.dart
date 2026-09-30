import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../domain/layer.dart';
import '../widgets/property_controls.dart';
import 'layer_fields.dart';

class PropertyOptions extends StatelessWidget {
  const PropertyOptions({
    super.key,
    required this.editor,
    required this.layer,
    required this.properties,
    required this.editable,
  });

  final EditorController editor;
  final Layer layer;
  final PropertyProperties properties;
  final bool editable;

  @override
  Widget build(BuildContext context) => PropertyGroup(
    title: 'OPTIONS',
    children: [
      LayerColorField(
        editor: editor,
        layer: layer,
        value: properties.color,
        choices: OutlineColor.propertyChoices,
        change: (c) => properties.copyWith(color: c),
        enabled: editable,
      ),
    ],
  );
}
