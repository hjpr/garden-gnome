# Canvas implementation plan

## Scope and status

This is the engineering companion to the [completed Flutter Build workthrough](flutter-build-workthrough.md). B01–B16 there govern user behavior; the [Build API](index.html#build-api) contains the corresponding model and operation reference. The user delegated remaining prebuild defaults while preserving the existing strategy. Decisions are complete for this scope; implementation still requires explicit authorization.

The application is not built by this document. Existing Node models and the HTML layout study remain unchanged. No documentation tests, acceptance-test tables, or link checks are required. Application-code tests and native/web execution belong to the implementation phase.

The original canvas architecture is retained: authoritative geometry, reference-based ownership, CanvasControl interaction state, CanvasDisplay presentation state, CanvasController transactions, and read-only painting. This plan now incorporates the completed Layers/persistence contracts rather than keeping them outside an earlier planning scope.

## 1. Document, geometry, and interaction state

### Ownership

- A document has a stable UUID, ordered root Field IDs and Reference IDs, a layer registry, geometry registry, allocation/name high-water marks, and immutable assets. Each Plot has one Field; each Area one Plot. References remain outside the land hierarchy beneath land.
- Layer owns id/name/properties and references one geometry instance via outline. Child membership/order and parent ownership agree. Menus reference the layer, not copied property objects. UUID IDs and names are independent; manual duplicate names are allowed after nonempty/single-line/120-character validation.
- Geometry owns its Point/LineSegment/Circle/ClosedShape registries. Point alone owns world coordinates. A segment refers to local start/end Point IDs, never copied endpoints. Cross-layer joins or shared Points are prohibited; coordinate coincidence does not imply identity.
- Keep existing local point-N, line-N, circle-N, shape-N formats. Allocate on accepted transactions only; counters never rewind on Undo/deletion. Local workspace high-water metadata and saved maxima merge on load. Redo restores original IDs. This is document-lineage bookkeeping, not distributed coordination across independent copies.

### Concrete references and geometry records

```text
Document
  document_id: UUID
  layers: map<LayerId, Layer>
  root_fields: ordered list<LayerId>
  references: ordered list<LayerId>
  geometries: map<GeometryId, Geometry>
  name_counters: Field / Plot / Area / Reference high-water values
  assets: immutable asset manifest/store

Layer
  id, kind, name, parent_id
  children: ordered list<LayerId> (land only)
  outline: GeometryId
  properties and existing type-specific fields

GeometryRef
  layer_id, geometry_id, kind (point/line/circle/shape), item_id

Geometry
  id, owner_layer_id, kind (field/plot/area)
  points, lines, circles, shapes: maps keyed by local ID
  last_ids: points / lines / circles / shapes
  boundary: null or {kind: shape|circle, id}

Point: id, x, y (world metres)
LineSegment: id, start (Point.id), end (Point.id)
Circle: id, center (Point.id), radius (metres), pattern
ClosedShape: id, segments [{segment_id, reversed}], pattern
AreaGeometry adds dimensions.flat / dimensions.row / dimensions.mound

ReferenceGeometry
  id, owner_layer_id, kind: reference
  points and last_ids.points
  anchor: Point.id or null
  metres_per_pixel: positive finite number or null
  reference_line: null or {start: image_local_xy, end: image_local_xy}
```

This is a language-neutral model sketch, not a YAML runtime format. Typed Dart IDs/references and enums prevent resolving a Circle ID as a Point. Use maps and a dependency index for incident segments/circles; rebuild/update indexes within transactions. Serialized document records occur once in keyed registries, not expanded copies on layers.

A ClosedShape retains identity and surviving segment membership after deletion, even while open; completeness is derived. Remove dangling references, not retained geometry. Repair extends identity-connected membership rather than switching to an unrelated loop. A complete cycle has at least three Points/segments with shared identities at every join. Polygon-to-circle construction requires explicit removal of surviving boundary segments; there is no silent Replace action. Circle deletion clears its designation and retains its center.

### Interaction

```text
Canvas
  document: current document
  control: CanvasControl
    interaction
      selected_layer: LayerId or null
      selected_geometry: ordered set<GeometryRef>
      active_tool, active_function
      tool_function_memory: map<ToolId, FunctionId>
      snap_target: GeometryRef or null
      active_operation: operation context or null
  display: CanvasDisplay
  preview: tool-specific Preview or null
```

Selection is layer-local. Canvas hits inspect only selected-layer records; choose layers in Layers. Point/edge/interior category priority, distance, and numeric-ID tie-break are deterministic. Point acquisition is 8 logical px, edge/outline/insertion acquisition 6 px, movement threshold 4 px. New Point center spacing is one displayed diameter, initially 6 px; this is not world validity tolerance.

Plain selection replaces; Shift toggles, and grouped translation/deletion is included in milestone 1. No marquee/lasso/persistent groups. Selecting one item updates snap_target; selecting a group does not. Deletion clears removed references, not unrelated state. Reselecting the same layer expands Properties without resetting drawing. Ineligible ancestors block mutation, not inspection. An unavailable existing snap target remains remembered but produces no guides.

## 2. Layer properties and drafts

Properties remain on their owning layer. Area dimensions stay in AreaGeometry; AreaProperties.planting_type chooses their active presentation. Field/Plot color choices, drainage enum, and null defaults remain the documented values. Basic controls and later-stage controls follow workthrough B01; do not add an Area color property or treat crop-name text as a seed assignment.

- Ordinary valid text/numbers commit on Enter/blur; optional blank becomes null; unchanged values preserve precision and add no action.
- Invalid ordinary blur retains draft/error while its panel is available. Escape/Revert restores the committed value.
- Rename requires Save/Cancel. Preferences drafts require Apply/discard; minimize retains them, close discards unapplied settings.
- A different layer or Properties close commits valid ordinary old-owner input, discards invalid/unsaved rename drafts, then changes presentation. Same-layer reselection only expands.
- Minimize settles valid ordinary input, retains invalid drafts/rename. Planting-type changes block on invalid outgoing drafts and otherwise settle before hiding fields; committed settings remain for later reuse.
- Unit changes inspect all pending length drafts, even minimized/blurred, commit valid old-unit values first, and block on invalid ones. One foot is 0.3048 metres. Angles use degrees; screen widths use logical pixels; soil observations are not length values.
- Layer-delete confirmation intercepts focus/blur: Cancel restores exact drafts/focus, Confirm discards deleted-owner drafts and deletes committed data. Undo restores committed data, not drafts.
- Drawing Undo/Redo is disabled while unapplied property drafts exist; local text Undo never falls through to document history. Save/leave settlement is explicit in section 7.

Use one draft coordinator, keyed by document/layer/field, for button, keyboard, focus, panel, and command transitions. Prevent double commit and old-owner data applying to a new layer. Do not depend on event-handler order to produce a transaction.

## 3. Panels, focus, and display

CanvasDisplay retains the documented colors, units, menu scaling, property-menu references, and panel states hidden/minimized/expanded. visible_menus is derived, not separately writable. Stable panel IDs remain drawing_tools, settings, layers, field_properties, plot_properties, area_properties, reference_properties, preferences. At most one property panel is visible. Top-bar dropdowns are not workspace panels.

Fixed overlay layout: tools/settings left, layers/properties right, centered Preferences. Panels scroll internally or within side rails when space is crowded; no drag/dock. Full editing minimum is 800×600 logical px; below it expose a resize message and safe Save/Close. Panel changes do not resize the viewport or move the camera. Menu scaling is independent of drawing zoom.

Focus follows visible reading order; hidden/minimized bodies leave traversal. Layer selection keeps focus in Layers, closing a panel returns to its opener/canvas, and modal/menu closure consumes the triggering gesture. Escape has one owner: modal/dropdown, focused draft, active operation, then geometry selection. It does not cascade into unrelated panels or geometry.

Status area carries tool/prerequisite prompts, selection count, and invalid construction reasons; title shows unsaved state. Keep Layers validity icon-only, compact read-only Active/Inactive in Properties, and light-grey angled hatching for closed inactive regions. Open outlines have no fill or implied edge. Provide accessible names/valid-blocked cues without mandatory invalid-drag notifications or new status tooltips. Incomplete-parent Add explanations stay the approved text on hover and keyboard focus; wrong selection has its own prompt.

Render references below land, parent interiors below descendants, outlines above fills, and previews/selection above geometry. Mask ancestor decoration beneath descendant interiors. Decorative Fill does not control invalid hatch. PlotProperties.pattern is the only Plot fill owner; its boundary-record pattern remains null. Field/Area pattern lives on their designated shape/circle.

## 4. Viewport, coordinates, and validity

- World lengths are metres, x right/y down. At 100% zoom one metre is 30 logical px. Camera stores viewport_position.current at the drawing rectangle's top-left, not its center.
- Obtain the viewport rectangle from layout in logical pixels. Header/status bar are outside; panels overlay inside without changing the rectangle.
- Shared transform per axis: screen = (world − camera_top_left) × 30 × zoom; use the inverse for input. Reuse it for painting, hits, previews, and snapping. Do not store derived visible bounds independently.
- Pointer-anchored zoom preserves the point beneath the pointer. Resize preserves the previous world center without changing zoom. Existing multiplicative wheel steps, zoom limits, and breakpoint grid formulas remain those in CanvasControl; grid stays anchored to origin.
- canvas_size describes positive finite extent or both-null unbounded extent, not window size or a land boundary. Drawing/panning outside is allowed; changing extent never deletes/crops geometry.
- View Fit includes committed geometry/usable references, excludes candidates, accounts for overlay gutters, respects limits; empty Fit resets. Reset is 100%, origin at top-left.

Validity is shared between candidates, commit, history, and detached loading. Use robust predicates and fixed distance tolerance 1e-8 m; region area must exceed tolerance times boundary perimeter. Never use hit radius or display rounding as topology equality. No self-contact, self-crossing, retracing, collapsed edges, branches, duplicate connections, or sibling interior overlap; collinear vertices and allowed point/edge contact remain.

Contain entire child segments/circles, not just their endpoints, in valid parents. Parent edits/reclosure must contain retained descendant construction geometry too, even inactive/incomplete children. Do not move descendants or hide them from validation. Active is derived from complete valid own geometry plus valid ancestors, independently of selection. Intentional deletion can reopen parents and retain inactive children; invalid movement rolls back instead.

## 5. Controller transactions and history

Input → CanvasController command → draft/context settlement → candidate/final validation → atomic model/reference/history update → derived eligibility/cache invalidation → view notification. Painting never changes model or menu state. Validators and geometry algorithms are separate domain services, not a giant controller method. UI widgets request edits rather than mutating geometry.

Commands use typed payloads with owner, target records, starting revision and immutable before/after state. Serialize mutations through the controller. Build and validate proposed changes before publishing; on failure do not partially update document or history. Model notifications occur once coherent state is ready. Asynchronous import/generation results carry document/layer/request revisions and cannot publish after their owner/context changes.

ActionsBuffer uses structured inverse records. PlacePoint Undo executes its RemovePoint inverse and retains recovery data for Redo. Snapshot removed records and ownership, not only live references. Group Point+segment placement, insertion/split, common movement, connected deletion, selected-set deletion, layer subtree changes, properties, Circle operations, and reference transformations atomically. Generated output is derived from parameters, not thousands of separate actions.

Default capacity 50 groups, integer 1–1,000 in Preferences, shared across Undo and Redo. Transfer does not add a slot. New committed edits clear Redo; no-ops, rejected values, navigation, selection, tools, panels, and Preferences do not. Overflow evicts oldest Undo; shrinking trims oldest Undo then furthest-future Redo. Eviction never changes geometry. Keep asset bytes while document/history/save snapshots reference them.

Replay preserves surviving current selection; removed references clear, restored objects are not auto-selected. Counters do not rewind. Failed replay retains document/history, reports a brief failure, and never skips the failed entry. History survives Save but not reopen. Saved state compares user content independently of history cursor/allocator counters; never mark later revisions saved accidentally.

## 6. Tools, Preview, and live operations

### Preview lifetime

Canvas.preview contains the selected tool's PreviewPoint/PreviewLine/etc., or null if it has no preview. Its drawing method is called directly in the normal paint pass; no callback registry. Controller updates candidate geometry/validity outside painting. Keep active_operation's context distinct from the tool's visual candidate; clearing a candidate need not destroy the selected tool's Preview capability.

The active operation contains target layer, tool/function, operation token, starting values, and current anchor where applicable. Token is transient, not a document ID. History can carry before/after Line context for eligible replay; the live anchor is not looked up by scanning the capacity-limited buffer. History eviction cannot make an active preview disappear.

### Tool behavior

- Point Move/Place/Delete; Line Draw/Join/Move/Delete; circle tools Draw/Resize/Delete; Reference Move/Scale/Reference Line; Fill None/Dots/Crosshatch/Crosses. First-use Point Move, Line Draw, circles Draw, Reference Move, Fill None. Remember functions during a session; reset on reopen.
- Line commits each accepted Point and segment immediately. Dashed pointer candidate remains transient. Join reuses eligible same-layer endpoints/isolated Points; no edge-interior acquisition, third incident segment, or silent merge. Point Place inserts on an edge first if needed.
- Enter/Escape or tool/function/layer switch preserves placed Line geometry, including a lone start. No Backspace preview stepping or repair mode. Returning to Line starts fresh; explicit endpoint attachment continues an existing path.
- In the same uninterrupted Line operation, Undo of A–B removes B/segment and resumes from A. Undo of a newly created A leaves Line waiting for a start with eligibility for immediate Redo. Reused A is never deleted by cancelling its context. Redo restores an ongoing anchor or completed state without trailing preview. Retain completion's token only for immediate history until another operation/context change.
- Different tool/function/layer, explicit Enter/Escape, capture loss, document transition, a new operation, or an unrelated committed document edit ends prior replay-context eligibility. Same-tool reselection, temporary pan/zoom, and Save do not. After switching away/returning, replay may restore geometry but never revive old drawing context.
- Circle first clicks stay temporary. Center-diameter uses center then circumference or numeric diameter; two-point uses opposite diameter ends and stores only derived center/radius. Successful Circle creation is one atomic action. Circle center moves with Point Move; fixed-center Resize validates radius; Circle Delete retains center, Point deletion removes dependent Circle.
- Group movement deduplicates defining Points and applies one common displacement with fixed descendants. Invalid release restores original positions. Direct Delete functions affect the hovered item; canvas Delete acts on selected set. No reconnection/orphan cleanup.

### Input ownership and snap anchors

Middle-drag or Space+primary-drag pans when no text editor owns Space. Wheel zoom belongs to the canvas unless over a panel. Pan between drawing clicks preserves the operation. During held geometry drag ignore navigation/extra pointers; release over a panel/outside cancels. Capture loss/deactivation cancels transient context while preserving placements. Click-only tools suppress a click after displacement beyond 4 logical px rather than inventing a drag.

Identity attachment uses 8 px; insertion/outline hits 6 px; Drawing alignment 6 px per axis. Filter eligible selected-layer endpoints first, choose nearest then ID, highlight one, and let it outrank grid/alignment. Point insertion stays projected and still checks spacing. Movement snapping never joins identities. Grid uses nearest visible intersection; ties lower x then y. Drawing snapping uses retained-item Points/endpoints/centers, excludes all Points being moved, permits per-axis alignment, and ranks distance then ID.

Translate a group using one grabbed anchor and preserved pointer offset: grabbed Point, nearest endpoint for segment, nearest boundary Point for interior, center for Circle. Reference transformations/sample picks are unsnapped. Existing but unavailable targets remain stored without guides; deletion clears them. Disabled tools stay selected/inert with a prerequisite prompt.

### Later derived and asset operations

Reference import owns immutable bytes, normalized dimensions, world anchor/uniform scale, and image-local samples. Decode before commit; stale requests cannot overwrite a different layer. First fit is uncalibrated; replacement keeps center/width, clears calibration. Scaling clears known distance; moving preserves it. Calibration fixes first sample in world and applies scale from positive distance; null/zero remains unfinished. Workthrough B11 governs limits and missing-asset recovery.

Area settings stay in AreaGeometry. Edge-to-edge spacing, clockwise row direction, clipped strips, whole-disk mound lattice, and active-only generation follow B12. Generated footprints are read-only/cached, not editable boundary records or serialized copies. Invalidate stale output immediately and publish only a matching input revision. Camera/unit changes do not regenerate. Limit candidate workload and keep UI cancellable rather than silently publishing a partial result.

## 7. Persistence, commands, and restoration

### Draft and leave coordination

Preflight ordinary drafts for Save/Save As by owner/original units; invalid blocks before any draft commits. Require explicit Rename/Preferences settlement rather than auto-accepting them. Then commit changed valid ordinary input once and capture the save revision. Save serializes all committed Points/segments/open outlines, not a candidate, and keeps active drawing available if staying in the document.

New/Open/Close with dirty content or pending drafts shows Save/Discard/Cancel without incidental blur settlement. Save uses the same command path and leaves only on success. Cancel preserves exact data/drafts/context. Discard takes effect only once the destination transition succeeds. Failed/cancelled Save/Open retains work; valid ordinary input explicitly settled before saving remains committed/undoable, with no additional failure mutation. This clarifies the earlier shorthand “unchanged” on failure.

Load a detached candidate before replacing the current document. New assigns a new identity/default settings; Close returns to empty app shell. Save As creates a new identity only on success, preserving internal IDs and session history and copying applied settings. Cancellation leaves the current identity/location intact.

### Storage contract

Native saves a .ggnome ZIP container via verified temporary write and safe replacement, retaining the previous good version on failure. Detect externally changed destinations before overwrite. Web baseline explicitly saves to browser IndexedDB with transactional document/assets, revision readback, and clear not-cloud-backup wording. Browser Open also imports portable files; Export uses the same container but download initiation is not verified persistence and does not clear an unsaved state. Direct native save-path APIs are not assumed available on web.

```text
Portable document.json (schema version 1)
  format: garden-gnome
  schema_version: 1
  document_id: UUID
  canvas_size: {width: metres|null, height: metres|null}
  root_fields: ordered LayerIds
  references: ordered ReferenceLayerIds
  name_counters: type -> high-water integer
  layers: LayerId -> record with kind, parent_id, children, outline GeometryId,
          name, properties, and type-specific crop/ground where applicable
  geometries: GeometryId -> owned typed registry record
  assets: AssetId -> {path, sha256, media_type, pixel_width, pixel_height,
                      byte_length, availability}
ZIP assets/<safe-entry-name>: immutable encoded image bytes
```

Availability distinguishes present versus known missing/corrupt asset placeholders; do not replace missing image references with null. Preserve available corrupt bytes for explicit recovery rather than executing/decoding blindly. Geometry registries contain authoritative records once; do not serialize runtime reference cycles, preview, history, Active flags, or generated layout.

Detached load validates version/features, unique IDs, typed/owned references, no hierarchy cycles/shared children, consistent order, finite numbers/enums/bounds, counter maxima, boundary topology/containment and asset metadata. Incomplete geometry/inactive descendants are legitimate. Reject structural corruption/newer unsupported formats instead of pruning/merging records. Missing images alone permit placeholder recovery. No legacy format migration is needed from the unsaved JS prototype.

Safety limits: 100 MiB compressed container, 256 MiB expanded content, 16 MiB JSON, 100 images; each image at most 20 MiB encoded/40 megapixels. Reject duplicate entries, absolute/traversing paths, and over-limit decompression. No imported code or automatic remote retrieval.

Persist applied workspace settings, view, and non-property panel states separately by document identity. Persist/merge local high-water bookkeeping even when user content returns clean. Reopen with no selection/snap target, closed Properties, Point Move, no drafts/function memory/history. A restored Preferences panel displays applied settings only.

Application-controlled leave supports the full flow. Browser-controlled tab close/reload can only request the browser's generic warning after interaction and is not reliable; no asynchronous-save promise at termination. Register warning only while dirty/drafts. Forced native termination also cannot guarantee recovery. Autosave/cloud/crash snapshots are deliberately not introduced. Quota/storage-denial/write errors retain in-memory work and offer retry/export.

## Flutter handoff

Create the app in flutter/ only after authorization. Pure-Dart domain and validators feed application/controller services, Flutter presentation/painters, and native/web persistence adapters. Start with built-in notifier/listenable state, shared typed command results, immutable assets, and owned drafts. Pin only inspected compatible packages; file_selector is a candidate for native dialogs/browser import, not web save locations. ZIP/UUID/digest/IndexedDB dependencies remain replaceable engineering choices behind interfaces.

The inspected planning environment exposes Flutter 3.38.9 stable, Dart 3.10.8, Linux, and Chrome. No Flutter project has been built, no app tests/device runs are claimed, and no SDK upgrade/install is part of this task. First targets are Linux x86-64 (Ubuntu 24.04 baseline) and desktop Chrome/Firefox on Linux. Other OS/browser/mobile targets remain explicitly unverified/deferred.

Implement domain/history/codec foundations, then a complete boundary editor journey, remaining interaction/properties, and native/browser recovery before milestone 1 is complete. Circles/Fill/observations, references/calibration, and generated layout follow. Full W01–W06 narratives and application-code verification commands/budgets are in [B15–B16](flutter-build-workthrough.md#b15--complete-user-journeys).

Initial measured-workload targets are 200 land layers/10,000 Points+segments, 100 ms ordinary feedback, a 60 Hz navigation frame budget, and two-second geometry-only save/open on a named machine. These are engineering budgets, not claimed results. Profile native and web separately, bound caches/generation, use culling/indexes, and do not assume a native isolate strategy automatically works on web. Missed budgets or a necessary major strategy reversal must be reported, not hidden.

## Documentation status

Prebuild decisions and narrative journeys are consolidated; older open-question prose and coordinate-closed polyline examples are superseded by the identity-connected segment model. The historical log in the workthrough is reference-only. No documentation test suite or validation run was performed for this closure. The deliverable is the specification and execution handoff; the remaining gate is authorization and then real application implementation/verification.
