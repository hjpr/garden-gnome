# Garden Gnome (Flutter)

The current web app: Home, Plan, Seed Vault, Greenhouse, Grow and Harvest.
Plan draws **properties and zones**, including curved boundaries, holes,
ground/rows, features and reference images. Plant mode places varieties on
grow zones; the other tools track varieties, sowing and harvest calendars.

User guides: [Plan](../docs/plan-guide.md) and
[garden tools](../docs/garden-tools-guide.md).

## Run and verify

Run these commands from `flutter/` with Flutter installed and Chrome available:

```sh
flutter pub get                    # first setup or dependency changes
flutter run --no-pub -d chrome
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub          # release output: build/web
```

The root `npm test` also runs this Flutter suite. Root
`npm run test:prototype` runs only the retained Node prototype tests.

## Code boundaries

- `lib/domain/`: pure Dart records, geometry, land rules, row/plant layouts
  and growing-calendar rules. Coordinates and stored lengths are in metres;
  display units are separate. No Flutter or downstream imports.
- `lib/application/`: controllers, history/drafts, tool/input behavior and
  storage contracts. Document edits go through the editor's commit/history
  boundary. Garden-record state is owned separately from drawing state.
- `lib/persistence/`: versioned drawing and garden-record codecs, catalog
  loading, and concrete browser storage adapters.
- `lib/presentation/`: app navigation, screens, panels, reusable controls and
  canvas rendering. Widgets adapt input and display controller/domain state.
- `lib/platform/`: conditional browser implementations and non-web stubs.
  These facades are intentional dependencies of composition/presentation,
  not the bottom of a strictly linear layer stack.
- `lib/main.dart`: startup and adapter composition.

Drawing geometry stores straight, circular-arc and Bézier edges. Line/arc
region math is analytic; Bézier edges use arc approximations for land math.
Do not substitute rendered paths for domain calculations.

## Data and assets

Drawings use `.ggnome` files and browser IndexedDB. Per-drawing workspace/view
settings and the garden record (varieties, plantings, climate) have separate
storage and lifetimes. Export a drawing to keep a copy outside the browser;
it does not export the garden record.

`assets/icons` links to `../../src/icons`, which is live shared artwork.
`assets/render/` and `assets/catalog/` contain bundled runtime assets. Do not
copy this directory without its icon target or confuse it with the retained
Node/layout prototypes described in [the root README](../README.md).

## Tests

Place tests by the behavior under test: pure rules/math in `test/domain`,
controller/input behavior in `test/application`, codecs/adapters in
`test/persistence`, and rendered controls in `test/presentation`.

Reusable builders and widget harnesses belong in `test/support`, never in a
runnable `*_test.dart` imported by another suite. Keep numerical expected
values independent of production calculations. Isolated panels need scrolling
and controller listening; full-app tests should keep their own navigation and
storage setup rather than inheriting a panel harness.

The long design documents under `../docs/` are historical references. Use the
two current guides above for implemented behavior.
