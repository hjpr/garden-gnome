# Garden Gnome

Farm management, starting with the documentation.

Open `docs/index.html` in a browser. No install or build step is needed.

Edit `docs/index.html` to change the outline. An article's H1 is its sidebar
label; its H2s become subsection links automatically on reload. Add
`data-parent="build-api"` to an article to place its page under the separate Build API section.
Pages have their own fragment URLs within the same file, so direct local
viewing still works. Keep existing IDs stable for bookmarks. New H2s can omit IDs.

Document model shapes and examples in language-neutral YAML. Shape blocks describe
types, relationships, and defaults; example blocks contain data, not constructors.
This is documentation notation, not a YAML loader or a change to the runtime models.

Styles live in `docs/styles.css`; sidebar behavior lives in `docs/navigation.js`.
Shared UI icons and pattern swatches live in `src/icons/` as standalone SVG files.
DrawingTools documents each tool's `icon`, `display_name`, and `context_menu_name`.
Icon paths are relative to the repository root; HTML pages in `docs/` use `../src/icons/`.
The diagrams are placeholders. The first Build data models are in `src/build/`:
`Field` contains `Plot` instances, each containing `Area` instances.
Geometry, the drawing tool, and persistence are not implemented yet.

## Flutter Build workthrough

The [Build workthrough](docs/flutter-build-workthrough.md) consolidates the
prebuild decisions, staged scope, complete user journeys, and Flutter handoff.
The [canvas implementation plan](docs/canvas-implementation-plan.md) describes
the reference-based models, controller/preview responsibilities, and persistence
adapters. These are intended contracts, not implemented Flutter features.

The remaining gate is explicit authorization to implement. The first milestone
includes the straight-edged boundary editor, properties, Undo/Redo, and native/web
save/open; circles/Fill, reference images, and generated planting layouts follow.

## Tests

With Node.js 24 or later, run `npm test` for the models.
Documentation prototypes have no automated tests; browser tests are deferred until app development.
