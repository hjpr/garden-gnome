# Garden Gnome (Flutter)

The Build screen: the canvas editor where fields, plots and areas are drawn.
How to use it: ../docs/build-guide.md. The design decisions behind it:
../docs/flutter-build-workthrough.md (B01–B16).

## Run

    flutter pub get
    flutter run -d chrome     # develop
    flutter test              # all tests
    flutter analyze           # lint
    flutter build web         # release build in build/web

## Code layout

Each layer depends only on the ones above it.

    lib/domain/         Pure Dart. The drawing and its rules.
      vec, planar         points in metres and shared tolerance/predicates
      curve_edge, region  exact line/arc boundaries, holes and Boolean maths
      geometry            editable layer geometry, plus GeometryEditor
      layer, document     fields, plots, areas and the whole drawing
      land_rules          nesting and overlap checks between layers
      units               feet / metres (display only; storage is metres)

    lib/application/    Editor behaviour, no widgets. Testable headlessly.
      editor_controller   the one place every change goes through
                          (validate, record history, tidy selection)
      canvas_input        turns clicks and drags into tool actions
      history, drafts     undo/redo and unapplied Properties text
      camera, snapping, hit_testing, previews, tools, tool_prompts
      document_session    New, Open, Save, Save as, Import, Export

    lib/persistence/    Storage.
      document_codec      the .ggnome file (zip with document.json),
                          versioned and checked before it is opened
      drawing_library     drawings saved in the browser (IndexedDB)
      workspace_store     settings and view per drawing

    lib/presentation/   Widgets.
      build_screen        page layout, menus, shortcuts, status bar
      canvas/             painter and pointer handling
      panels/             Drawing tools, Settings, Layers, Properties,
                          Preferences
      widgets/dock        folding side docks with drag-to-reorder panels
      widgets/panel       panel chrome and shared controls
      dialogs, theme      dialogs; colours, sizes, Material theme

    lib/platform/       Browser-only bits (warn before closing the tab).

## Notes

- assets/icons is a link to ../src/icons, so the app and the docs share
  one set of icons.
- Circles: `Geometry.circles` (a centre point + radius). Additional closed
  shapes/circles can be staged as same-layer Boolean operands.
- Edges store a signed arc bulge (zero means straight). Closed shapes have
  an outer ring and hole rings. Region calculations use exact line/arc maths,
  not rendered paths or polygon approximations of circles.
- Schema 2 saves arc curvature and hole rings; schema 1 files still open.
- Milestone 2 scope and remaining work: ../docs/milestone-2.md. Decorative
  Fill and extended recorded properties remain; images, rows and mounds are
  later milestones.
