import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/presentation/theme.dart';

Future<void> setTestViewport(
  WidgetTester tester, {
  Size size = const Size(1200, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget testApp({required Widget child}) => MaterialApp(
  // Avoid the platform-dependent sparkle shader without changing layout.
  theme: buildTheme().copyWith(splashFactory: InkRipple.splashFactory),
  home: Scaffold(body: child),
);

/// The caller owns the controller and registers its disposal with addTearDown.
/// Use a bounded, non-scrolling body for panels with their own flex/scrolling.
Widget editorPanel({
  required EditorController editor,
  required WidgetBuilder builder,
  double width = 264,
  double? height,
  bool scrollable = true,
}) => testApp(
  child: SizedBox(
    width: width,
    height: height,
    child: ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final body = builder(context);
        return scrollable ? SingleChildScrollView(child: body) : body;
      },
    ),
  ),
);
