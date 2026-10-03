import 'package:flutter/material.dart';

import '../application/app_tools.dart';
import '../application/document_session.dart';
import '../application/garden_controller.dart';
import 'plan_screen.dart';
import 'garden/garden_page.dart';
import 'garden/greenhouse_screen.dart';
import 'garden/grow_screen.dart';
import 'garden/harvest_screen.dart';
import 'garden/seed_vault_screen.dart';
import 'home_screen.dart';

/// Shows the open tool, or home. Plan is kept alive while another tool
/// is open (Offstage), so switching back keeps its view, panels and any
/// half-typed values.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.navigator,
    required this.session,
    required this.garden,
  });

  final AppNavigator navigator;
  final DocumentSession session;
  final GardenController garden;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([navigator, garden]),
    builder: (context, _) {
      final tool = navigator.current;
      return Stack(
        children: [
          Offstage(
            offstage: tool != AppTool.plan,
            child: TickerMode(
              enabled: tool == AppTool.plan,
              child: PlanScreen(
                session: session,
                navigator: navigator,
                garden: garden,
              ),
            ),
          ),
          if (tool != AppTool.plan) _gardenTool(tool),
        ],
      );
    },
  );

  Widget _gardenTool(AppTool? tool) {
    if (tool == null) return HomeBody(navigator: navigator, garden: garden);
    return GardenPage(
      navigator: navigator,
      toasts: garden.toasts,
      body: switch (tool) {
        AppTool.seedVault => SeedVaultBody(garden: garden),
        AppTool.greenhouse => GreenhouseBody(garden: garden),
        AppTool.grow => GrowBody(garden: garden),
        AppTool.harvest => HarvestBody(garden: garden),
        AppTool.plan => const SizedBox.shrink(),
      },
    );
  }
}
