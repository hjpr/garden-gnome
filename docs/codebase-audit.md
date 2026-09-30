# Codebase organization audit

Snapshot: 2026-09-29, main at 30172f3, including the existing working-tree changes.
The findings and source line references below preserve the original read-only audit. They describe that snapshot, not the current implementation. See [Implementation status](#implementation-status) for the subsequent cleanup and verification.

## Conclusion

The architecture is worth keeping. The domain is independent of Flutter, most small modules are cohesive, and document edits generally have a recognizable controller boundary. The problem is concentrated responsibility: several files have accumulated multiple jobs, and independent features now share selection, preview, persistence, and construction state in ways that are not obvious from their names.

This is not a rewrite recommendation. Repair the data/state ownership defects first; then extract real functional boundaries, reduce misplaced dependencies, and tidy names and comments. Splitting a large class into more `part` files alone does not make it more self-contained.

## Scope and verification

The parallel source review covered all 118 production Dart files (25,363 lines), the structure of all 36 Flutter test suites and two support files, the package manifests, repository layout, entry-point documentation, current guides, and prototype/tooling boundaries. Long test bodies were reviewed structurally rather than treated as measured execution coverage. Historical design documents were not reinterpreted as instructions to undo later features.

Measured production files: domain 26, application 29, persistence 6, presentation 43, platform 13, main 1.
Measured test suites: domain 9, application 17, persistence 2, presentation 8. These are file counts, not coverage percentages.

Executed against this snapshot:

- `cd flutter && flutter analyze --no-pub`: exit 0, no issues.
- `cd flutter && flutter test --no-pub --reporter json`: exit 0, 436 passed.
- `npm test`: exit 0, 13 legacy Node model tests passed. This does not test Flutter.
- Separate scratch regression probes: 18 cases, one control passed and 17 intended safety/consistency assertions failed. These reproduce the defects below; they are not failures in the existing 436-test suite and are not claimed to be 17 independent root causes.

The probes use delayed in-memory drawing storage and mocked SharedPreferences. No real browser records were read or written. There was no browser interaction, release build, visual comparison, performance benchmark, or numerical-accuracy certification in this audit.

The import inventory includes `part` directives and every conditional-export branch. All 118 production files are reachable in that graph from main; no orphan Dart file was confirmed. There are no Flutter/downstream imports in domain and no material/widgets/cupertino imports in application. Application-to-persistence imports remain in DocumentSession and GardenController.

## P1 — Fix before extending the affected features

### S1. Save completion can overwrite newer work

Evidence: flutter/lib/application/document_session.dart:95-110; flutter/lib/application/editor_controller.dart:98-113.
Status: reproduced with three failing probes and one passing control.

`_write` captures a document before awaiting storage, but then operates on the session's current `_editor`. Save As installs the old snapshot as the current document, not just its new identity. The result can discard edits made while the write is pending. A save completing after New can replace that newly opened document with the earlier drawing. Even ordinary Save restores the old title after a rename made during the write.

The control confirms that ordinary Save on the same editor retains intervening geometry edits; the defect is not that every save discards every concurrent edit.

Repair the ownership boundary: capture the originating editor and saved metadata; do not update another editor when the write finishes. Apply a Save As identity to the originating editor's latest content without replacing that content. Record the saved snapshot/title separately from the current title. Define how overlapping file commands are ordered. Add delayed-adapter tests for edits, renames, document switches, and overlapping saves before changing this code.

### S2. Recovery from an unreadable garden record is destructive

Evidence: flutter/lib/application/garden_controller.dart:45-78; flutter/lib/persistence/garden_record_store.dart:23-36.
Status: reproduced using the real browser-store adapter with mocked preferences.

When decoding fails, including a newer schema version, `load` leaves the fallback empty record and sets loaded=true. The next edit saves that fallback over the unreadable record. The probe seeded a version-99 record and observed it replaced by a version-1 record after adding a variety.

Use explicit loading/ready/load-failed state. Prevent persistence after failed recovery until a successful reload or an intentional reset/recovery decision; retain the original bytes. Keep controls and mutation commands consistent with that state. Distinguish catalog failure from user-record failure rather than treating both as permission to proceed with writable defaults.

### S3. The immutable snapshot boundary has writable escape routes

Evidence: flutter/lib/domain/geometry.dart:145-154,270-278; flutter/lib/domain/region.dart:67-70; flutter/lib/domain/reference_image.dart:41-56,80-81.
Status: six failing probes demonstrated input aliasing or writable cached collections.

ClosedShape keeps caller-owned segment and hole lists, including nested holes. Geometry exposes mutable cached stack and closedIds lists. PolygonRegion keeps its input corners, and ReferenceImage keeps writable input bytes. A caller can therefore change an allegedly immutable value without a controller transaction, history entry, dirty-state update, or cache invalidation.

Copy and freeze collections at ownership boundaries, including nested lists. Freeze derived collections exposed as part of a snapshot. Accept reference-image data through a defensively copied, read-only payload and reuse that payload for metadata-only copies; do not copy a large image on every move or opacity change.

The same static issue exists in Crop.sections/estimated (flutter/lib/domain/grow/crop.dart:98-122,162-167) and HardinessZone.all (flutter/lib/domain/grow/climate.dart:19-25). Include these siblings in the fix. The audit demonstrates that mutation is possible, not that a current UI action already mutates every one of these collections.

### S4. Garden-record decoding does not enforce identity integrity

Evidence: flutter/lib/persistence/garden_record_codec.dart:37-72,95-112,127-148.
Status: three failing probes for version 0, duplicate variety IDs, and missing counters.

Nonpositive versions are accepted; duplicate IDs silently replace earlier records in map construction; a missing counter defaults to zero even with existing IDs, allowing the next ID to collide. Several malformed optional values also become absent values instead of errors. The document codec has substantially stricter structural checks.

Check supported versions, uniqueness, references, and the counter floor. Refuse damaged user data, or perform explicit compatible migration without losing identities. Distinguish missing optional values from malformed present values. A tolerant bundled-catalog importer and a user-record reader do not need the same repair policy.

## P2 — Consolidate inconsistent editing policy

### B1. Click and drag choose different objects

Evidence: flutter/lib/application/canvas_input.dart:88-95,168-179,356-365; flutter/lib/application/canvas_reference.dart:39-56; flutter/lib/application/canvas_feature.dart:20-38.
Status: reproduced. A click selected a raised bed, but a drag from the same location moved the reference image underneath it by one metre.

Hover/click consider features before reference interiors; drag startup tries a reference image before a feature. Resolve the selectable target once using shared policy for hover/click/drag. Preserve explicit selected-handle priority, point/edge priority, locked-object filtering, and Plant-mode restrictions.

### B2. A misleading selection helper changes unrelated state

Evidence: flutter/lib/application/editor_controller.dart:343-356,1217-1223.
Status: reproduced. Switching to Feature cleared the selected feature despite the immediately adjacent preservation logic.

`_clearReferenceSelection` also clears feature selection. Split reference-only and feature-only clearing, or use a broader name only where both are intentionally cleared. Audit its callers rather than patching only the one tool transition. This is a naming problem with behavioral consequences, not a spelling preference.

### B3. Preview ownership is represented two different ways

Evidence: flutter/lib/application/editor_controller.dart:1051-1058,1128-1153.
Status: reproduced at the controller boundary.

Boolean recognizes its own preview by type. Align maintains a separate flag that survives cancellation/general preview replacement. A later Align exit clears a newer unrelated preview. Put operation ownership in the preview value or use one explicit ownership mechanism; only the current owner should clear a preview.

### B4. Cross-layer sorting drops established hit tie-breaks

Evidence: flutter/lib/application/hit_testing.dart:79-90,115-123.
Status: reproduced with 100 equal-distance points. Per-layer order started at point-1; the cross-layer re-sort started at point-34.

The second comparator returns equality for same-layer ties and relies on a sort stability guarantee Dart does not provide. Preserve the per-layer rank or use the same final stack/ID tie-break. Test overlapping shapes as well as equal-distance point/edge hits.

### B5. Delete availability is duplicated in the widget

Evidence: flutter/lib/presentation/build_screen.dart:591-598; flutter/lib/application/editor_controller.dart:1361-1373.
Status: source-confirmed; no dedicated menu interaction probe added.

The menu checks geometry/reference selection but not features, while deleteSelection supports a selected feature. Expose controller-owned availability for the same command so menu and keyboard do not drift. Include lock and mode policy when defining that predicate.

## P2 — Extract actual functional boundaries

### A1. Separate geometry records, editing, and validation

Evidence: flutter/lib/domain/geometry.dart:11-547,550-1338,1356-1609. Total: 1,609 lines.

This library contains the geometry records and queries, the mutable GeometryEditor/topology/Boolean implementation, and independent validity checks. These are distinct responsibilities, not merely an arbitrary line-count violation.

Suggested boundaries: geometry.dart for records/queries, geometry_editor.dart for editing, geometry_rules.dart for validation. Extract shared traversal/contour calculations where needed. Keep the model from depending on the editor, for example by putting the edit convenience extension with the editor. Do not make all private members public simply to permit a mechanical split.

### A2. Reduce EditorController's independent responsibilities

Evidence: flutter/lib/application/editor_controller.dart:390-446,522-619,964-1357,1473-1581. Total: 1,581 lines.

Keep document ownership, commit/history coordination, and selection invariants together. Extract cohesive workspace commands and feature/reference/operation behavior through narrow collaborators or functions with explicit inputs. Group transient construction state and its reset semantics; the reset is copied across cancellation, commit, and history restoration. `_dropStaleReferences` also assigns `_referenceLineImageId = null` twice at 1454-1456.

Move document-content comparison out of this controller (1474-1560), but first specify and test its identity-sensitive layer comparison. ArcPoint/CircleStart describe unfinished application interaction and should stay in application, not be mislabeled as domain entities. If CounterLedger is extracted from domain/document.dart:325, keep mutable session accumulation in application and provide an immutable counter-floor value to domain/persistence.

More `part` files can be an intermediate navigation improvement, but would still share the whole controller's private state. They are not the end goal.

### A3. Make canvas input a router, not another accumulation point

Evidence: flutter/lib/application/canvas_input.dart:382-574,600-944; flutter/lib/application/canvas_construction.dart:211-251; flutter/lib/presentation/canvas/drawing_canvas.dart:81-85,131-148,192-249.

CanvasInput is 1,014 lines and its seven-file library totals 2,098 lines. Point, straight-line, circle, ordinary move/resize behavior remain in the dispatcher while other tools have separate parts. Feature placement is in canvas_construction despite the dedicated canvas_feature file.

Group tool state with the tool's behavior; keep the main input API focused on routing and shared gesture coordination. Move feature placement beside feature dragging. Extract common selection-target and gesture arbitration policy before rearranging files. Widget-specific focus, cursor, popup placement, and Flutter-event adaptation stay in presentation; pan/tool arbitration and outside-release policy can be tested as application behavior.

### A4. Split composition-heavy UI files at recognizable components

These are candidates because they contain independently named responsibilities, not because every large widget must be fragmented:

- flutter/lib/presentation/build_screen.dart:469-852 (869 lines total): extract BuildHeader and BuildStatusBar; keep camera/scale readouts private to the status bar. Retain lifecycle and page orchestration in the screen.
- flutter/lib/presentation/canvas/scene_painter.dart:39-119,236-418 (835 lines; 1,794 with five parts): separate SceneState from paint orchestration and group land painting together. Wireframe rows currently live in render_painter.dart:342-370. SceneState contains rendering types and belongs in presentation, not domain.
- flutter/lib/presentation/garden/seed_vault_screen.dart:276-751 (751 lines total): separate variety details, CropNotes, and the add-variety dialog from list/filter/selection orchestration.
- flutter/lib/presentation/panels/layers_panel.dart:95-707 (707 lines total): group reference/image rows separately from land/shape rows; extract LayerActions, which is independently used by BuildScreen.
- flutter/lib/presentation/panels/properties_panel.dart:17-448,513-650 (650 lines total): leave selection routing/shared heading here; separate property and zone editors and the substantial inline-name editor, following FeatureProperties/ReferenceProperties.
- flutter/lib/presentation/widgets/panel.dart:6-78,85-222,245-345: separate icon controls, dock chrome, and property-form controls rather than importing panel chrome for an icon.

Small private widgets used only by their parent should generally remain beside it.

### A5. Separate storage contracts, adapters, and serialization jobs

Evidence: flutter/lib/application/document_session.dart:4-6; flutter/lib/application/garden_controller.dart:12; flutter/lib/persistence/garden_record_store.dart:9-61; flutter/lib/persistence/document_codec.dart:44-103,107-248,261-435,591-679,749-796.

Application currently imports implementation-layer modules to acquire interfaces, codecs, and concrete workspace storage. GardenRecordStore also contains an asset-catalog loader and a test-only memory implementation. The 796-line document codec combines ZIP transport/assets, JSON mapping, old-schema migration, structural validation, and primitive readers.

Place storage contracts/errors where application can own its dependencies; inject browser adapters at main. Move catalog loading to a focused loader and the instrumented memory store to test/support. Keep a small .ggnome facade over JSON conversion and structural validation; do not make a file for every tiny entity reader. Preserve schema compatibility explicitly.

Standardize adapter failure contracts: garden save currently throws a format error for a write failure, workspace save ignores a false write result, and drawing deletion exposes raw backend failures (garden_record_store.dart:30-35; workspace_store.dart:99-145; drawing_library.dart:134-138).

### A6. Put shared helpers below their consumers, not inside a screen

Source-confirmed dependency tangles:

- layers_panel.dart:8 imports scene_painter.dart solely for layerColor at scene_painter.dart:832. Move the domain-to-Color adapter into shared presentation styling, not domain.
- greenhouse_screen.dart:10 and harvest_screen.dart:9 import grow_screen.dart for shared calendar helpers. Move calendar range/timing presentation into a screen-independent module; extract ClimateBar and its input adapter (grow_screen.dart:13-46,223-317).
- Home and Build import garden/tool_switcher.dart for app-wide navigation. Put ToolSwitcher/toolIcon in shared presentation; keep the garden-only header with GardenPage.
- garden_page.dart:47,111 exports Card2 and Chip2 from a page-frame module. Rename them by role, such as GardenCard and StatusChip, and locate reusable components independently of the page frame.
- garden_record_codec.dart:9 imports crop_catalog_codec.dart for encodeRange/decodeRange at 82-92. Share a small range codec, preserving a distinction between catalog tolerance and persisted-record strictness.

Avoid creating a generic utils.dart that just becomes the next unrelated collection.

### A7. Share text-editing mechanics without merging different lifecycles

Evidence: flutter/lib/presentation/garden/commit_field.dart:11-132; flutter/lib/presentation/widgets/draft_text_field.dart:13-171; flutter/lib/presentation/panels/feature_properties.dart:108-237; flutter/lib/presentation/panels/reference_properties.dart:198-339.

Focus, text controllers, Enter/Escape, commit/error handling, and inline rename/delete behavior are repeated. However, CommitField and DraftTextField are not interchangeable: Build drafts participate in save/undo/layer-switch settlement. A single naive replacement would erase important behavior.

Extract only controller-neutral field/inline-name mechanics. Keep a Build-specific draft wrapper and the numeric/unit MeasureField adapter. Move crop range parsing out of a generic text widget. Test Enter, blur, Escape, external undo updates, layer switches, and disabled fields before consolidating.

### A8. Consolidate duplicated calculations deliberately

Evidence: flutter/lib/domain/geometry.dart:1586-1599 and domain/curve_region_kernel.dart:16-30 contain two signed-area calculations, with compensated summation only in the latter. application/alignment.dart:108-134 and application/transform_box.dart:84-106 duplicate item-bounds logic with different incomplete-shape treatment.

Share the well-tested contour-area primitive and item-bounds mechanics. Keep policy separate: TransformBox's requirement for a whole shape is not itself duplication. Characterize behavior before changing numeric code; sharing code must not silently alter geometry tolerance or open-shape handling.

Smaller cleanup: measurement formatting is repeated in panels/measure_field.dart:99, reference_properties.dart:437, and preferences_panel.dart:87. Use one named display formatter after unit conversion.

## P2/P3 — Make the repository describe and test the current product

### R1. Entry-point documentation and the default test command are stale

Evidence: README.md:3-5,21-40; flutter/README.md:3,23,56-64; package.json:5-7; docs/build-guide.md:35.

The root README says geometry/persistence are unimplemented and only advertises npm test. Flutter's README still uses the Field/Plot/Area hierarchy and describes implemented reference/row work as future scope. The guide's quick start says Line → Draw even though the function is Straight.

Update the two entry-point READMEs for the current Flutter app and its actual run/analyze/test/build commands. Link both current guides. Label the old Node models and layout studies as retained prototypes/design references. Expose the legacy runner as test:prototype and make the default test entry point unambiguously direct users to Flutter (or run both explicitly). Do not silently present the 13 Node tests as application verification.

Keep the long historical design documents unchanged. src/icons is live: flutter/assets/icons resolves to ../../src/icons. The old docs also link prototype source; deleting src wholesale is not safe cleanup.

### R2. Test boundaries and shared setup have drifted

Evidence: flutter/test/application/align_test.dart:8 and plant_mode_test.dart:13 import other runnable test files for helpers. application/toasts_test.dart includes widget cases; garden_controller_test.dart:54-80 includes codec cases. application/boolean_tools_test.dart:304-695 and presentation/boolean_tools_test.dart include unrelated arc/camera/formatting/tool-layout behavior.

Extract small editor-input and geometry/document builders into test/support instead of importing a test suite. Keep mathematical expected results independent of production helpers. Share an explicit widget harness for theme, viewport, scrolling, controller listening, and teardown without forcing full-app and isolated-widget tests into the same setup.

Move direct codec tests to persistence, pure curve/row math to domain, and rendered controls to presentation. Name suites by current behavior; retire milestone_gaps_test.dart as a catch-all. Boolean controller tests and Boolean widget tests are complementary, not duplicate suites just because their basenames match.

The audit's delayed-storage, load-failure, mutation, and interaction-transition cases are more important additions than merely increasing the number of test files. Existing tests cover many happy paths but missed these boundaries.

### R3. Preserve the current feature work when tidying repository contents

The starting tree already had 32 modified tracked paths and 24 untracked status entries (some entries are directories). Those untracked garden controllers/screens, catalog assets, icons, tests, and scraper files are active feature work, not disposable clutter. Review them as a complete set before a future commit; this audit makes no commit.

Flutter build/.dart_tool and root test-results are ignored. Specific render-art work/output directories are not; add targeted ignores for intermediates, keeping selected runtime render assets tracked. Do not perform blanket cleanup of untracked files. A stale ignored test-results marker is not evidence of Flutter correctness and is not a priority refactor.

## P3 — Names, comments, dead APIs, and local consistency

### C1. Correct misleading explanations before adding more comments

Evidence:

- domain/geometry.dart:88 promises an exact Bézier closest point; domain/bezier.dart:64-88 uses sampled search and local numerical refinement.
- domain/bezier.dart:6-9,91-117 promises a fixed error bound, but fitting samples selected parameters and accepts the depth cap without another error check. Treat the bound as unproven; if 0.5 mm is a required guarantee, enforce/test it rather than merely weakening the comment.
- domain/row_layout.dart:100-109 calls sampled parameter positions eight-direction extrema. Rename the helper to describe sampling or implement true extrema in separately tested numerical work.
- presentation/canvas/curve_paths.dart:106-130 claims close-up work is limited to visible length, but the loop visits offsets along the full path before culling extraction/drawing.
- domain/grow/climate.dart:60-77 cites unspecified extension-service tables and applies a fixed half-zone adjustment at 41-47. Supply actual provenance/rationale or identify application heuristics; do not invent a source.

Delete comments that only restate obvious declarations, such as “Whether layerId is a grow zone.” Keep comments explaining units, ownership, aliasing, numerical limitations, compatibility, browser workarounds, and undo/draft semantics. Do not impose boilerplate file headers or a doc-comment quota. Section-divider comments are not automatically a defect; a repeated need for them can be a clue that independent responsibilities need separation.

### C2. Remove verified unused surfaces, not compatibility data

Repository usage searches found no callers outside the unused cluster in domain/planar.dart:22-72,90-167 for segmentsCross/segmentsTouch/intersectionsAlong/polygonArea/polygonPerimeter/polygonContainsSegment/polygonsOverlap and their private helpers. Retain tolerance, PointLocation, closestPointOnSegment, distanceToSegment, and locatePoint, which are used.

Other small unused surfaces include ToolFunction.drawsCircle (application/tools.dart:93), GardenController.updatePlanting (application/garden_controller.dart:186), and daysToIdeal (domain/grow/planting_windows.dart:91). PlantLayout.lineLength is computed without a consumer; this is distinct from the live ReferenceImage.lineLength. The point-delete helpers in canvas_input.dart:401-416,681-685 still carry unreachable line branches after removal of Line → Delete.

Recheck callers immediately before deleting any API. Make genuinely local helpers private, not all public classes indiscriminately. Retain PlantingDimensions compatibility fields (domain/geometry.dart:183-200) unless an explicit, tested migration preserves their values; “not currently rendered” is not permission to discard saved data.

### C3. Standardize names and shared visual tokens without a restyle

Card2/Chip2 are priority naming fixes because they do not explain their role. Circle.center differs from the domain's usual centre; normalize internal identifiers only when touching that surface, without renaming Flutter SDK parameters or serialized keys. Correct stale test descriptions such as “patterns” when assertions test labels. The frost half-zone test should state ±5 days from the base or 10 days between halves, rather than leave the reference point implicit.

Theme centralization is incomplete: repeated reference/guide blue, error colors, typography, pane widths, radii, and shadows are spread through presentation (for example build_screen.dart:507-510, widgets/toaster.dart:184-191, canvas/reference_painter.dart:5, garden/garden_page.dart:53-81). Consolidate shared design tokens/component styles into theme.dart or focused styling modules. Keep one-off layout structure, geometry constants, shader masks, and user-selected colors local. Do not create dozens of meaningless named constants solely to eliminate every number.

High-tunnel image-section rounding in domain/feature.dart:27-36 is a rendering policy whose production consumer is feature_painter; keep exact stored dimensions in domain and place the rendering approximation beside its consumer.

### C4. Give temporary UI resources an owner

Evidence: presentation/dialogs.dart:75-115,120-150 creates TextEditingControllers without disposing them. canvas/scene_painter.dart:743-762 and canvas/reference_painter.dart:137-156 repeat measurement-label painting with temporary TextPainters.

Use stateful dialog content to own/dispose its editing controller. Share the small canvas measurement-label renderer and dispose temporary TextPainters after use. This is source-level lifecycle hygiene, not a measured memory-growth finding.

## What should stay

- The domain/application/presentation separation; no framework rewrite or new dependency-injection framework is justified.
- Small cohesive modules such as vec.dart, curve_numeric.dart, curve_edge.dart, land_rules.dart, camera.dart, history.dart, toasts.dart, and app_tools.dart.
- The app-shell composition, shared GardenPage/Timeline patterns, and the small text-focus/browser workaround modules.
- The analytic line/arc region kernel as a cohesive implementation. Its `part` relationship is not evidence of dead code or a requirement to publish its private helpers.
- Conditional platform facades. Document them as intentional leaves usable from composition/presentation; do not manufacture abstractions for every tiny browser call solely because an old README's linear list places platform last.
- SeedsBody in editor panels: it edits grow zones on the drawing, so that placement is functional rather than accidental.
- Distinct persistence formats for drawings, browser workspace state, and the gardener's record. They have different ownership and lifetimes.

The preliminary audit's suggestions that missing file headers or // versus /// were inherently problems are not retained. Nor is the suggestion that ArcPoint/CircleStart belong in domain, or that CommitField and DraftTextField do exactly the same job.

## Recommended cleanup sequence

1. Add production regression tests for S1-S4, then fix storage ownership/recovery and immutable boundaries. Include the sibling load/save paths, not just the first failing call.
2. Centralize selection-target, preview-owner, cancellation, and command-availability policy; fix B1-B5 with focused tests.
3. Split geometry records/editor/rules and extract the shared calculation helpers. Keep history/commit as the single document-change path.
4. Extract cohesive editor/input and UI modules, plus shared styling/navigation/calendar helpers. Separate behavior changes from mechanical moves so diffs remain reviewable.
5. Reorganize test fixtures/suites, update entry-point documentation, and remove confirmed unused code/redundant comments while touching their modules.

After each bounded change: analyze and run the relevant/full Flutter tests. For widget/painter changes also rebuild web and exercise affected flows in the browser; compare representative render output before claiming no visual change. Preserve the existing schema and approved features unless a deliberate migration is separately agreed. No arbitrary maximum file size, one-class-per-file rule, mass reformat, or comment-stripping pass is recommended.

## Temporary audit evidence

Scratch location (subject to normal scratch cleanup):
/home/hjpr/.hermes/profiles/claudetrial/cache/scratch/garden-gnome-audit/

- inventory.json: counts, import/part graph, and source hashes.
- structural_risks_test.dart: isolated reproductions, intentionally red on this snapshot.
- verification.json: commands, return codes, counts, and failure messages.
- analyze.log, flutter-tests.log, audit-probes.log, prototype-tests.log: raw outputs.

Run the probes from the Flutter project directory with:

    flutter test --no-pub --reporter expanded /home/hjpr/.hermes/profiles/claudetrial/cache/scratch/garden-gnome-audit/structural_risks_test.dart

Probe accounting: one normal-save control passed; save ownership/title 3, failed-load recovery 1, decoder integrity 3, immutable collections 6, feature tool transition 1, click/drag target 1, preview ownership 1, and hit tie-breaking 1 failed. This report records the scenarios so its findings remain useful after the temporary evidence is cleaned up.

## Implementation status

The approved stabilization and first functional-boundary cleanup are implemented. This is not a claim that every optional extraction or numerical concern above is resolved. Existing feature work, historical plans, file schemas, and the shared icon asset link were preserved; no commit was made.

### Verified fixes

| Findings | Current result | Regression evidence under `flutter/test/` |
| --- | --- | --- |
| S1 | Saves retain their originating editor, snapshot and title; writes are serialized. Save As adopts identity without replacing intervening edits. Workspace failures remain separate from a confirmed drawing save. | `application/save_ownership_test.dart`, `application/document_session_test.dart` |
| S2, S4 | Unreadable/newer garden records block mutations instead of being overwritten. The user-record reader checks versions, identities, references, counters and malformed values. Adapter failures use application-owned errors. | `application/garden_controller_test.dart`, `persistence/garden_record_codec_test.dart`, `persistence/storage_adapters_test.dart` |
| S3 | Shape/ring inputs, exposed geometry lists, polygon corners, reference bytes, crop collections and hardiness-zone lists are frozen. Metadata-only reference copies share the frozen payload. | `domain/immutable_models_test.dart`, `domain/grow_planner_test.dart` |
| B1, B2, B4 | Select hover/click/drag share target precedence; overlay/land selection transitions are exclusive; cross-layer hit ordering retains tie-breaks. | `application/select_target_test.dart`, `application/selection_policy_test.dart`, `application/boolean_tools_test.dart` |
| B3, B5 | Preview values own refusal feedback; stale operation exits leave unrelated feedback alone. Delete availability and execution share controller policy, including frozen objects and Plant mode. | `application/operation_feedback_test.dart`, `application/selection_policy_test.dart`, `presentation/build_composition_test.dart` |
| C4 | Dialog state owns text controllers. Shared measurement labels and timeline labels dispose temporary text painters. Narrow dock labels/actions fit the real panel width. | `presentation/name_dialog_lifecycle_test.dart`, `presentation/measurement_label_test.dart`, `presentation/build_composition_test.dart`, `presentation/garden_screens_test.dart` |

### Current ownership

- A1: `domain/geometry.dart` owns records/queries, `geometry_editor.dart` owns mutation and its convenience extension, and `geometry_rules.dart` owns validation. Shared contour area is in `curve_contour.dart`; the model does not depend on its editor. Geometry API, area, Boolean and codec regressions pass.
- A2/A3: `application/construction_state.dart` owns unfinished construction and matching history restoration; `drawing_input.dart` owns point/line/circle commands; `selection_target.dart` owns Select precedence. Snapshot comparison and identifiers have independent modules. The controller retains document/history and selection coordination; canvas input retains shared gesture routing. Further command/gesture extraction is still possible, but no arbitrary file-size target was imposed.
- A4/A6: Build header/status, scene state, land/plant painters, layer actions/fields, property/zone editors and reusable controls have named owners. Garden screens consume independent calendar, climate, variety-detail, crop-note and dialog components. App-wide navigation no longer belongs to a garden screen. `GardenCard` and `StatusChip` replace the numbered names.
- A5: Application owns document/garden/workspace storage and codec contracts; startup injects adapters. `.ggnome` archive transport is separate from document JSON conversion/validation. Catalog loading, shared range encoding and test memory storage have separate homes.
- A7: Crop-range parsing is separate from generic commit fields. Build drafts and immediate-commit garden fields retain their different lifecycles; shared inline-name editing mechanics were not consolidated in this pass.
- A8: Area integration and item bounds are shared. Bounds retain explicit policy for open-shape Align versus closed-shape transforms. Small display-formatting duplication remains a follow-up.
- R1–R3: Current READMEs and guides describe the Flutter product. Root `npm test` runs Flutter; `npm run test:prototype` runs the retained Node models. Shared test fixtures live under `test/support`, runnable suites no longer import one another, and pure row/soil/unit and ground/seed codec cases live under domain/persistence. Render-generation intermediates have targeted ignores; active untracked work was not deleted.
- C2/C3: The verified unused planar helper cluster was removed and touched component names/styles improved. Remaining small unused APIs, identifier spelling and optional visual-token consolidation were not treated as prerequisites to the safety/ownership fixes.

### Verification of the cleaned tree

- `flutter analyze --no-pub`: exit 0, no issues.
- `flutter test --no-pub --reporter json`: exit 0, **551 passed**, no test errors. The final test-boundary move preserved all 45 source/destination test declarations and their expectations.
- `npm run test:prototype`: exit 0, **13 passed**.
- `flutter build web --no-pub`: exit 0; the server at `http://127.0.0.1:8765/` returns HTTP 200. The build emits a non-fatal missing Cupertino icon-font warning; the build is successful, not warning-free.
- Six representative painter rasters match the captured pre-extraction RGBA baselines byte-for-byte: wireframe/render rows, selection, move preview, circle label and reference label. This is a bounded comparison, not a whole-UI pixel guarantee.
- Fresh-profile headless Chrome smoke: **63 steps, 13 assertions, no runtime exceptions**. Exercised rectangle creation, feature placement/drag, history controls, Wireframe/Render, saving/reloading/reopening a drawing with its feature, adding/reloading a Seed Vault variety, and navigation through Greenhouse, Grow and Harvest. Screen captures were inspected. Test data remained in the isolated scratch profile, not the user's normal browser profile.
- The import/part/conditional-export graph contains **154 reachable production modules**. Domain remains Flutter-free and acyclic; application does not import persistence/presentation; preview/transform values do not depend on the controller. There are **61 runnable Flutter test files**, with no local runnable-test imports.
- `git diff --check`: clean. `flutter/pubspec.lock`: no diff. No dependency addition was required by this cleanup.

Current scratch evidence is `cleanup-tests.jsonl`, `cleanup-test-summary.json`, `boundary-checks.json` and `browser-final/results.json` under the audit scratch directory above. Raster evidence is under the sibling `build-presentation-cleanup/` directory. These files may be pruned; the maintained regression suites remain in the repository. The original scratch audit probes refer to pre-extraction APIs and are historical reproductions, not the current verification command.

### Explicit follow-ups and limits

- C1 numerical work remains separate: the Bézier 0.5 mm guarantee has not been certified, and sampled row bounds are not exact extrema. Neither a passing suite nor these extractions proves those stronger numerical claims.
- The frost-date heuristic still needs sourced provenance/rationale, and the full-path culling explanation needs reconciliation with its algorithm. Do not infer agronomic accuracy or viewport-proportional performance from this cleanup.
- Further inline-field sharing, controller command extraction, display formatting, small unused-API removal and optional style-token consolidation remain discretionary follow-ups, not silently completed items.
- No performance benchmark, Firefox/GPU-specific validation, exhaustive browser gesture coverage or populated-calendar browser scenario was run in this pass. Populated garden behavior has widget/domain coverage; the browser calendar smoke used empty planting lists.
