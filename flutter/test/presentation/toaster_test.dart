import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/toasts.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/presentation/widgets/toaster.dart';

import '../support/widget_harness.dart';

void main() {
  testWidgets('the toaster sits at the chosen edge with an error icon', (
    tester,
  ) async {
    final toasts = ToastCenter();
    addTearDown(toasts.dispose);
    Future<void> pump(ToastPosition position) => tester.pumpWidget(
      testApp(
        child: Toaster(toasts: toasts, position: position),
      ),
    );
    await pump(ToastPosition.bottom);
    toasts.show(
      'Add a Property layer to start drawing.',
      kind: ToastKind.error,
    );
    await tester.pumpAndSettle();
    final text = find.text('Add a Property layer to start drawing.');
    expect(text, findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
    final screen = tester.getSize(find.byType(Scaffold));
    expect(tester.getCenter(text).dy, greaterThan(screen.height / 2));

    await pump(ToastPosition.top);
    await tester.pumpAndSettle();
    expect(tester.getCenter(text).dy, lessThan(screen.height / 2));

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(text, findsNothing);
  });
}
