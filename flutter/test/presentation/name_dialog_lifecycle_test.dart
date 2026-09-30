import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/presentation/dialogs.dart';

import '../support/widget_harness.dart';

void main() {
  for (final forShape in [false, true]) {
    final kind = forShape ? 'shape' : 'drawing';
    for (final action in ['submit', 'button', 'cancel', 'barrier']) {
      testWidgets('$kind name dialog owns its controller through $action', (
        tester,
      ) async {
        String? result = 'pending';
        const initial = 'Suggested name';
        await tester.pumpWidget(
          testApp(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await (forShape
                      ? askForShapeName(context, initial)
                      : askForName(context, initial));
                },
                child: const Text('Open name dialog'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open name dialog'));
        await tester.pumpAndSettle();
        final field = find.byType(TextField);
        final controller = tester.widget<TextField>(field).controller!;
        expect(controller.text, initial);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: initial.length),
        );
        final typed = forShape && action == 'button' ? '' : ' New name ';
        await tester.enterText(field, typed);
        switch (action) {
          case 'submit':
            await tester.testTextInput.receiveAction(TextInputAction.done);
          case 'button':
            await tester.tap(find.text(forShape ? 'Rename' : 'Save'));
          case 'cancel':
            await tester.tap(find.text('Cancel'));
          case 'barrier':
            await tester.tapAt(const Offset(4, 4));
        }
        await tester.pumpAndSettle();
        expect(result, action == 'submit' || action == 'button' ? typed : null);
        expect(find.byType(AlertDialog), findsNothing);
        expect(() => controller.addListener(() {}), throwsFlutterError);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Open name dialog'));
        await tester.pumpAndSettle();
        final reopened = tester.widget<TextField>(find.byType(TextField));
        expect(reopened.controller, isNot(same(controller)));
        expect(reopened.controller!.text, initial);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      });
    }
  }
}
