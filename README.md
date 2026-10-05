# Garden Gnome

A Flutter web app for planning land and growing food. Home opens the tools:

- **Seed Vault:** keep varieties and their growing requirements.
- **Plan:** in Build mode, draw properties and zones with straight lines,
  curves, arcs, circles and polygons and edit ground, rows, features and
  reference images; in Plant mode, place Seed Vault varieties on grow
  zones.
- **Grow (Sow | Transplant):** sow in place or start trays to plant
  out, and follow them to harvest using the crop catalog and your frost
  dates.

Drawings save in the browser and can be exported as `.ggnome` files. The
Seed Vault, plantings and climate settings are a separate browser record.

## Use the app

- [Plan guide](docs/plan-guide.md): drawing, editing, saving and controls.
- [Garden tools guide](docs/garden-tools-guide.md): varieties, Plant mode and
  growing calendars.

## Develop and check

Install Flutter with a Dart SDK compatible with `flutter/pubspec.yaml`, and
Chrome for the development target. From the repository root:

```sh
cd flutter
flutter pub get                    # first setup or dependency changes
flutter run --no-pub -d chrome      # develop
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub          # release output: flutter/build/web
```

After dependency setup, `npm test` from the repository root runs the same
Flutter test suite. npm is only a convenience entry point; it does not install
Flutter or its packages. See [the Flutter README](flutter/README.md) for code
and test boundaries.

## Repository boundaries

- `flutter/` is the current application, its tests and bundled assets.
- `src/build/` and `tests/` retain the early Node model prototype. Its
  Field/Plot/Area model is not the current Property/Zone model. Run its tests
  separately with `npm run test:prototype` (Node.js 24 or later; no npm
  dependencies to install). These are **not** application verification.
- `src/icons/` is **live shared artwork**, not disposable prototype code:
  `flutter/assets/icons` is a symlink to `../../src/icons`. Keep the repository
  layout intact when building Flutter.
- `docs/index.html`, `docs/build-layout.*`, the
  [Build workthrough](docs/flutter-build-workthrough.md),
  [canvas implementation plan](docs/canvas-implementation-plan.md) and
  [milestone notes](docs/milestone-2.md) are retained design references/layout
  prototypes, not a list of current features or remaining work. The HTML
  studies can be opened directly in a browser.
- `tools/johnnys-catalog/` builds the bundled crop catalog; see its
  [README](tools/johnnys-catalog/README.md). `tools/render-art/` generates and
  processes artwork; selected runtime assets live in `flutter/assets/render/`,
  separate from ignored generation rounds and processing intermediates.
