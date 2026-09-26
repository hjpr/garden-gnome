# Flutter Build workthrough

## Purpose and authority

This is the consolidated behavior contract and implementation handoff for Garden Gnome's Flutter Build utility. Existing user approvals remain in force. The remaining defaults were selected under the user's delegation to finish prebuild decisions using best practices without changing the established strategy. They are design requirements, not claims of implemented Flutter behavior.

The decision phase is complete for the defined Build scope. Implementation still requires explicit authorization. Package versions, private method names, and equivalent internal algorithms are engineering choices, not another product questionnaire. Escalate only a material change to the contracts below.

The [Build API](index.html#build-api) describes the same model and operations. The [canvas implementation plan](canvas-implementation-plan.md) supplies the architecture and execution detail. The [HTML layout study](build-layout.html) is a visual reference, not production behavior to port indiscriminately. The historical decision log at the end records the discussion; superseded questions there are not active requirements.

Do not create documentation tests, acceptance-test tables, or link-check scripts. Test application code during implementation. No application code, prototype behavior, or dependencies are changed by this prebuild closure.

## Decision map

| Issue | Contract | Disposition |
| --- | --- | --- |
| B01 | Scope, platforms, milestones | Defined below |
| B02 | Layer creation, ownership, identity | Defined below |
| B03 | Geometry and authoritative boundary | Defined below |
| B04 | Validity and participation | Defined below |
| B05 | Selection and hit testing | Defined below |
| B06 | Point, Line, and Circle tools | Defined below |
| B07 | Connected edits, deletion, and Fill | Defined below |
| B08 | Input ownership and snapping | Defined below |
| B09 | Properties and drafts | Defined below |
| B10 | Layout, focus, and accessible feedback | Defined below |
| B11 | Reference images and calibration | Defined for later image milestone |
| B12 | Area settings and generated planting layout | Defined for later planting-layout milestone |
| B13 | Save, open, leave, and asset recovery | Defined below |
| B14 | ActionsBuffer and preview recovery | Defined below |
| B15 | Complete user journeys | Narrative handoff below |
| B16 | Flutter implementation sequence | Ready for implementation authorization; no runtime verification claimed |

## B01 — Scope and milestones

Complete this entire Build contract before coding; deliver it in stages.

- Milestone 1: native desktop and desktop web boundary editor. Fields, plots, areas; straight-edged boundaries; Point and Line tools; Shift-click multi-selection with common translation/deletion; containment and overlap; camera, grid, units, fixed panels, basic properties, history, and save/open. Recovery and persistence are required, not optional follow-ups.
- Milestone 2: both circle tools, circular boundaries, an Arc tool (three-point circular arcs), a Polygon tool (Regular and Rectangle), Boolean → Union/Subtract, editable boundaries with holes, net area and hole/arc-aware land validation, decorative Fill, and extended recorded layer properties. See [milestone 2 geometry scope](milestone-2.md) for the updated geometry contract; it supersedes the earlier no-holes/no-arcs and second-shape restrictions below. First-milestone invalidity hatching is not decorative Fill.
- Milestone 3: reference-image import, durable assets, movement/scaling, calibration, replacement, and recovery.
- Milestone 4: planting-type and row/mound settings with derived generation. Do not expose controls whose output is not implemented. Existing schema fields remain preserved even before their controls ship.
- Basic properties in milestone 1: names; Field/Plot existing color choices; optional Field drainage category; Plot ground text; Area crop name as a nullable label; read-only Active/Inactive. Areas remain Flat until milestone 4. Do not add an Area color property solely for symmetry.
- Numerical soil observations ship with extended properties, not agronomic calculations. Their limits are in B12.
- Deferred from this Build scope: marquee/lasso selection, persistent grouping, multiple disconnected occupied regions in one layer, layer hiding/locking/reordering, geometry rotation/nonuniform scaling, image rotation/cropping/skew, collaboration/cloud synchronization, autosave/crash drafts, touch and dedicated trackpad gestures, and crop suitability/seed/yield/schedule engines. Ordinary mouse-compatible trackpad events still use the mouse contract.
- Initial release targets: Linux x86-64 desktop (Ubuntu 24.04 LTS baseline) and desktop Chrome/Firefox on Linux. Record actual stable browser versions and machines when implementation is exercised. Windows, macOS, Safari, mobile, and other targets are not implicitly verified by Flutter support.

These stage assignments close earlier open placement of multi-selection, Fill, soil entry, and planting settings. They do not remove the later features from this document.

## B02 — Layers, identity, creation, and ownership

### Records and ownership

- One document owns ordered root Fields and References; each Plot has exactly one Field, each Area exactly one Plot. No shared children. Reference layers are outside the land hierarchy, beneath land; each new Reference goes beneath existing references.
- Document and layer IDs are generated UUIDs, stable and independent of names. One Geometry instance per land layer has a stable geometry ID and typed Point/LineSegment/Circle/ClosedShape registries. A layer's outline references that instance. No coordinate copies live in layer menus or dependent segments.
- Within a Geometry, retain local IDs point-N, line-N, circle-N, shape-N and high-water counters. An external GeometryRef contains layer_id, geometry_id, kind, and item_id; local segment endpoints contain Point IDs. Validate owner and kind on resolution.
- Allocate IDs only when a transaction is accepted. Rejection/cancelled previews consume none. Undo never rewinds counters; Redo restores original identities. Runtime lookups use maps keyed by ID and dependency indexes, not coordinate equality.
- Automatic names use document-wide nonrecycled counters per type: Field 1, Plot 1, Area 1, Reference 1. Skip a generated name already present for that type and consume the skipped number. Manual duplicates are allowed; hierarchy/type disambiguates them. Trim names and require a nonempty single line of at most 120 Unicode characters. Renaming never changes IDs, references, or order.
- Persist high-water marks; retain their maxima in local workspace metadata keyed by document ID, including after Undo. Reopening merges saved and locally known maxima. This prevents reuse in the document's saved/local lineage, not across independent historical copies on machines that share no allocation ledger. UUID layer IDs do not require such a ledger.

### Creation and defaults

- Add Field needs no selection. Add Plot requires the selected Field to have a completed valid boundary. Add Area requires the selected Plot and its Field to be valid. Do not select a different suitable parent automatically.
- Incomplete-parent explanations stay exactly `complete field before adding new plot` and `complete plot before adding new area`. Wrong/no selection uses the distinct prerequisite to select a Field or Plot.
- Create empty, select the new layer, open/expand its Properties, retain the current tool. Do not start drawing automatically. Empty Reference creation is separate from its file picker/import action.
- Field/Plot colors remain #465b3c/#99a18f. Soil values and drainage begin unassigned. Plot pattern and ground begin null. Area begins Flat, crop null, all row/mound dimensions null. Geometry collections and local counters begin empty/zero. Do not inherit a parent's or previously edited layer's values.
- Land sibling order is creation order. No per-layer hiding, locking, or manual ordering in the agreed scope.

### Deletion

- Confirm whole-layer deletion with the name and descendant count. Field deletion includes plots/areas; Plot deletion includes areas. One action restores the same records, properties, IDs, ownership, and order on Undo.
- Clear only affected selection, Properties, operations, and snap references; retain the tool, and do not auto-select a replacement. Unrelated selections/references survive. Draft handling is B09, not an accidental blur side effect.

## B03 — Geometry and authoritative boundary

### Concrete model

- Point owns finite world x/y in metres. LineSegment owns id, start: Point.id, end: Point.id. No separate Segment wrapper, embedded endpoint objects, middle-point map, or authoritative multi-segment Line record.
- Geometry owns points, lines (LineSegment records), circles, shapes, last_ids, and boundary: null or a tagged {kind: shape|circle, id} reference. A null boundary means none has been designated yet.
- ClosedShape owns id, an ordered list of {segment_id, reversed} references, and a nullable decorative pattern. Its references may be incomplete/disconnected after deletion; completeness is derived, despite the type name. Never keep references to deleted segments.
- A complete polygon is a connected simple cycle of at least three distinct Points and three noncollapsed segments. Adjacency and closure require shared Point identity, including the final corner, not coordinate equality. Reversing traversal does not reverse or duplicate the segment record.
- Circle owns id, center: Point.id, finite positive radius in metres, and pattern. Both circle construction methods produce this representation. The center is authoritative; two-point construction positions are temporary, not extra persistent controls.
- Pattern ownership for Plot versus Field/Area follows B07; do not create two independently writable effective fills.

### Construction and lifecycle

- Loose committed Points and open fragments are saved and editable but create no occupied land. The first valid closed loop or Circle becomes the authoritative boundary automatically. Reject a second independent closed region; use another layer.
- Once a polygon boundary is designated, retain its ClosedShape ID through edits/reopening/repair. Deleting segments removes their references; surviving membership remains. Newly joined repair paths extend that boundary through identity-connected endpoints. Do not promote an unrelated construction loop when the designated boundary is open.
- For a fully erased polygon, keep its empty boundary record so subsequent valid polygon construction repairs the same boundary. A Circle may replace it only after its surviving boundary segments are explicitly removed; that circle commit removes the empty shape designation atomically. No separate Replace-boundary mode or silent geometry deletion.
- Deleting a circular boundary removes its Circle/designation, retaining its center. It leaves no invented polygon. Undo restores it. A new shape may then become the boundary through ordinary tools.
- Do not automatically delete loose Points or paths on boundary completion. They remain ordinary layer-owned geometry subject to containment and same-layer crossing rules.
- Boundary linework has no branches: reject a third incident line segment, duplicate unordered endpoint connection, retracing, or an unconnected intersection. Multiple open fragments are permitted for construction/repair. Point insertion on an edge splits it; Line cannot silently turn an edge interior into a branch.

## B04 — Validity and participation

- Each layer has one occupied region. Holes and disconnected regions are deferred. Parent/child and sibling boundaries may share a point or edge without a mandatory gap. Sibling interiors may not overlap, contain one another, or duplicate one another. Fields likewise cannot overlap each other's interiors.
- No polygon self-crossing, retracing, nonadjacent self-contact/pinching, zero-length segment, or zero-area cycle. Ordinary adjacent joins and final closure are allowed. Retain collinear intermediate Points.
- Same-layer construction segments must not cross or touch unrelated segments without a shared endpoint identity. Across layers, evaluate region containment/interior overlap rather than banning every line crossing; construction geometry has no occupied region.
- A child edit requires valid ancestors. Its Points, entire segments, and circular region must stay within/on the parent, including across concavities. Open child fragments also follow containment.
- Parent movement/reclosure must contain all retained descendant geometry, including incomplete children, isolated construction Points, and inactive children. Children remain fixed; do not move, trim, resize, or delete them to make a parent edit valid.
- Moving connected geometry previews dotted affected neighbors; valid candidate green, invalid candidate red. Committed geometry is unchanged until valid release. Invalid release restores the original, not the last green candidate; no mandatory error notification. Invalid construction retains its rejected candidate plus a short reason and permits a new valid attempt or cancellation.
- Point/segment/boundary deletion may intentionally reopen a layer with children. Retain all descendant data; deactivate the subtree, block descendant geometry editing/new children, and repair ancestors first. Do not treat an intentional open outline as a failed movement.
- Active requires a valid complete own boundary and valid ancestors. Selection is independent. Inactive geometry is excluded from seed placement, boundary operations, crop/yield/harvest-window totals and calculations, not treated as valid zero-yield data. Repair/validation must still inspect its retained geometry. Recompute subtree participation after changes.
- Closed inactive interiors use light-grey angled hatch; open outlines have no fill or implied closure. Closed inactive children stay hatched under an open parent. Layers show a status icon only; Properties shows compact read-only Active/Inactive near the top. No status tooltip/reason-text expansion.
- Finite canvas extent is a display surface, not a clipping boundary. Drawing/panning beyond it is allowed; reducing extent never crops or deletes geometry.
- Use one world-space distance tolerance, 1e-8 metres, for degeneracy/contact classification, independent of zoom. Nonzero region area must exceed tolerance times boundary perimeter; use robust orientation/intersection predicates and consistent distance tests. Never round stored coordinates, merge identities, or use screen pixels to decide topological equality. Equality policy and predicates must be shared by preview, commit, history, and load.

## B05 — Selection and hit testing

- Canvas hits inspect the selected layer only. Use Layers to change drawing destination; a canvas click never silently redirects to another layer. Inspection remains possible beneath invalid ancestors, but mutation is blocked.
- Point → Move supports general click selection, but drags Points only. Line → Move drags segments or selected polygon interiors; circle Resize/Point center movement are B06. Click selection in Move functions ranks Point handles, then segment/circle outlines, then boundary interior. Layer selection and boundary selection remain distinct.
- Plain click replaces geometry selection; Shift-click toggles. Empty plain click clears geometry selection but retains selected layer and snap target; Shift-empty does nothing. Include Shift multi-selection in milestone 1; defer marquee/lasso and persistent groups.
- A drag on an already-selected eligible item translates the selected group; an unselected hit first becomes the sole selection. Expand selected edges/boundaries/circles into a deduplicated defining-Point set so shared Points move once. A selected circle moves by its center, not by changing radius.
- Single-item explicit selection updates snap_target. Group selection leaves it unchanged; removing an item from selection does not erase a still-existing target. Deletion clears it. An unavailable existing target remains referenced but supplies no guides. Inactivity alone does not remove known geometry coordinates.
- Initial logical-screen tolerances: Point/endpoint acquisition 8 px; segment/circle-outline hit and point-to-segment insertion 6 px; move gesture threshold 4 px. Keep separate named constants. Rank eligible hits by category, then distance, then ascending numeric ID suffix; external ties include owning IDs. Only one join/insertion target is highlighted.
- Creation selects its direct result: placed/inserted Point, newly committed segment, completed Circle. Closure does not unexpectedly select the whole boundary. Rejection/cancellation retains surviving selection. Undo does not automatically select restored objects.
- Reselecting the same layer reopens/expands Properties without cancelling drawing or clearing geometry selection. Reselecting the same tool/function is a no-op. Selecting a different layer/function/tool follows cancellation and draft rules.

## B06 — Tool flows

### Point

- First-use Move. Place previews a candidate, and primary click creates one Point. A Point within 6 px of an eligible segment projects onto it and inserts there; no fallback off-edge if projected placement fails validation.
- New Point centers must be at least one displayed Point diameter apart within the selected layer. Render markers with an initial 6 px diameter. This is a screen-space placement rule, independent of Grid/Drawing snapping. It never retroactively invalidates geometry on zoom changes. Existing Point moves obey geometry validity instead, and deliberate endpoint reuse creates no Point and is exempt.
- Inserting P in A–B removes the original segment and creates A–P/P–B with new segment IDs, updates boundary references, and preserves the region. One history action restores the original segment/ID on Undo. Points remain explicit even when collinear.
- Move grabs a Point and previews all dependent edges/circles. Delete hover-highlights and clicks one Point, removing its incident segments and dependent Circles together; never reconnect neighbors. Functions remain selected for repeated use.

### Line

- Functions: Draw, Join, Move, Delete. First-use Draw. Each accepted Draw placement is committed immediately: first Point, then each new/reused endpoint plus its connecting segment. Failed placement creates neither partial endpoint nor segment.
- A dashed segment runs from active_operation's anchor to the pointer. Hovering an eligible existing endpoint/isolated Point shows an outer ring; completing an attachment adds the union cursor cue. Reuse its identity. Joining is independent of Grid/Drawing snapping and has priority over those constraints.
- Click the next corner to continue; click a highlighted endpoint to join and finish. Clicking the start closes only after full validity checks. No new segment may give a Point more than two incident segments. Same-point/duplicate Join requests add nothing and keep the pending first endpoint available.
- Enter or Escape ends drawing and discards only the unplaced candidate. All accepted Points/segments remain, including a lone start. Finishing leaves Draw selected and ready for a fresh operation. No Backspace preview stepping or separate repair mode.
- Join clicks two existing eligible same-layer Points, previews between clicks, validates, and commits just the connection. Success keeps Join selected and starts a fresh pair next time. Escape cancels the pending pair without changing geometry.
- Line does not acquire segment interiors. Use Point → Place to split an edge first; a later connection still must obey no-branch rules. It never inserts/merges a Point silently.
- Move translates both endpoints equally, preserving length/angle and updating connected neighbors. Select a polygon interior with Line → Move to translate its defining Points; descendants stay fixed. Delete removes only the clicked segment and retains both endpoints and other connections. Hover/click Delete functions do not expand to an unrelated selection.
- Switching away clears the live anchor/dashed preview without deleting placements. Returning starts fresh. Continue explicitly by hovering/clicking the retained endpoint. Eligible Undo/Redo can restore context only as defined in B14.

### Circles — milestone 2

- Both tools expose Draw, Resize, Delete, first-use Draw. They produce the same center-reference/radius record; changing construction tool does not convert existing circles.
- Center-diameter: click center, move to preview circumference, click circumference to finish. Pointer distance is radius; display diameter. A focused positive numeric diameter in current units plus Enter may complete after choosing center. Enter without such input does not commit a hover candidate.
- Two-point: click opposite ends of a diameter. The midpoint becomes the center and half the distance the radius. Those clicked positions are temporary, not saved diameter Points.
- First clicks are temporary. Commit Circle, any newly created center Point, and boundary designation atomically after validation. Escape/tool/layer changes discard the uncommitted circle, unlike already accepted Line placements. Explicit center acquisition may reuse a highlighted same-layer Point. Otherwise apply new-Point spacing to the actual center, including a computed midpoint; reject without hidden merging.
- Apply the same one-boundary, parent containment, sibling non-overlap, and tangency policy as polygons. A new circle cannot silently replace surviving polygon boundary segments. Use ordinary deletion first.
- Success selects the Circle and retains the function. Point → Move on its center translates it with all other dependencies. Resize drags its circumference with center fixed or accepts numeric diameter, with live validity/invalid-release rollback. Delete removes Circle/designation but keeps its center. Point deletion of that center removes its dependent Circle.
- No line attachment to circumference, perimeter-point insertion, or arcs. Generated mounds are not editable Circle records.

## B07 — Connected changes, deletion, and Fill

- Common group translation applies one displacement to all distinct defining Points; validate atomically, including fixed descendants. No partial movement. Snap one anchor, never members independently. Whole-object rotation/scaling is deferred; Circle Resize is the explicit exception.
- Canvas Delete removes the selected set and required dependencies as one action. Direct tool Delete clicks affect the hovered item only. Deleting a polygon boundary removes its boundary segments but retains Points and unrelated construction. There is no separate multi-segment Line record to delete.
- Deleting a Point never reconnects its neighbors. Deleting a segment never removes orphan Points. Clean all affected record, boundary, selection, snap, and operation references in one coordinated change.
- Decorative Fill ships in milestone 2. Functions/patterns are None, Dots, Crosshatch, Crosses; first-use None. Choose pattern and click the selected layer's closed boundary interior. No flood fill of arbitrary construction fragments or other layers. Keep Fill selected.
- PlotProperties.pattern is the sole effective pattern for a Plot boundary; its shape/circle pattern remains null and is not independently editable. Fill and Plot Properties write that same field. Field/Area patterns live on their designated shape/circle record. No hidden competing overrides.
- Closed inactive boundaries may store a changed decorative pattern, but invalid hatch overrides it visually. Reopened polygon records retain their pattern; open outlines display none. Circle deletion deletes that circle's pattern, restored by Undo.
- Paint references first, then land parents before descendants, then outlines and selection/preview feedback. Mask ancestor interior decoration under descendant interiors to avoid stacked unreadable patterns. Persistent invalid styling is distinct from temporary green/red candidate feedback.

## B08 — Input, navigation, snapping

- Use shared viewport-local screen/world conversions. World metres, x right/y down; 100% zoom is 30 logical px/metre. Camera stores top-left world position. Panels overlay the viewport; header/status bar are outside it. Pointer zoom preserves the point under the pointer; resize preserves the previous world center at unchanged zoom.
- Wheel zoom retains documented multiplicative steps and limits. Grid spacing follows zoom breakpoints, anchored to world origin. Middle-drag pans; Space+primary-drag is the alternative when no text field owns input. Scrolling over a panel scrolls only the panel.
- A held geometry drag owns the gesture: ignore pan/zoom and extra buttons/pointers. Temporary pan between construction clicks preserves the operation and never places a point. Release over a panel or outside the viewport cancels a held edit. Capture loss/app deactivation cancels transient geometry work, preserving accepted placements.
- Click-only Draw/Join/Place/Delete accepts a click only if pointer displacement stays within 4 px. Crossing that threshold suppresses the click, not an implicit drag. Move functions begin their drag after the threshold. No click-through after closing a menu/dialog.
- Grid snaps new/moved anchors to the nearest visible intersection; ties prefer lower x then y. Drawing alignment uses retained-item Points, segment endpoints, and Circle center: 6 px per-axis threshold, nearest distance then stable Point ID. Both axes may constrain simultaneously. Exclude every Point moved in this transaction; unchanged anchors of the target may still guide it.
- Point/endpoint attachment (8 px) and segment insertion (6 px) remain independent of snapping. Highlighted attachment outranks alignment/grid. Point placement on an acquired segment stays projected on it; grid does not pull it away. Movement alignment never joins or merges identities.
- For segment dragging use the endpoint nearest the initial press (ID tie-break); for polygon interior dragging use the nearest boundary Point. Preserve initial pointer offset and apply one snapped translation to the entire group. Circular groups use the center. Reference image gestures are unsnapped.
- Disabled/unavailable tools remain selected but inert with a concise prerequisite prompt. Never silently switch Reference to Point. If a selected layer still exists but loses ancestor eligibility, keep selection for inspection and cancel its geometry candidate. Removal clears references.
- Keyboard: platform primary modifier+Z Undo, primary+Shift+Z Redo; Ctrl+Y also Redo on Linux/Windows. Primary+S Save, primary+Shift+S Save As, primary+O Open, primary+N New in app context. Text fields retain their local editing shortcuts. Do not override browser/system shortcuts when the app cannot safely own them.
- Escape is handled once: active modal/menu first, then focused draft, then canvas operation, then geometry selection. It never cascades through all levels or closes unrelated panels.

## B09 — Properties and drafts

- Menus reference owning layer data. Capture each draft's owner, field, original value, and display units. Apply at most once and never to a newly selected layer.
- Ordinary valid text/numbers commit on Enter or blur. Blank optional values become null; unchanged displayed values do not rewrite stored precision. Invalid blur retains the draft/error while its panel remains available. Escape or Revert restores the committed value.
- Immediate dropdown/color changes are one property action. Field/Plot colors and drainage keep documented enums. Names use B02 validation. Plot ground and Area crop are nullable text labels, not generation parameters or agronomic instructions.
- Rename requires Save/Cancel; Preferences uses a separate draft and Apply/discard. Closing Preferences discards it; minimizing preserves it. Applied workspace settings persist separately from drawing data.
- Switching layers or closing Properties keeps the approved behavior: commit valid ordinary fields to the old owner, discard invalid drafts/unsaved rename, then switch/close. Reselecting the same layer merely expands Properties.
- Minimize commits valid ordinary drafts once, preserves invalid ordinary drafts and unsaved Rename for reopening. Changing planting type validates/settles outgoing fields first; invalid drafts block the type change until corrected/reverted. Preserve committed hidden settings for later reuse.
- Unit changes examine all pending length drafts, including minimized/blurred fields. Commit valid drafts in their captured old units before conversion; any invalid length draft blocks the change. Do not reinterpret numbers. Store lengths in metres, display ft/m; one foot is 0.3048 m. Angles remain degrees; visual sizes remain logical pixels. Soil observations are not canvas lengths.
- Opening layer-deletion confirmation suspends blur settlement. Cancel restores the exact draft/focus without document changes. Confirm discards drafts belonging to the removed subtree, then deletes committed records. Undo restores committed data, not discarded form drafts.
- Drawing Undo/Redo controls are disabled while property drafts have unapplied changes; they cannot cause blur-commit then replay. Local field Undo/Redo still edits text, without fallback to document history. Save/leave use B13's explicit settlement, not arbitrary focus order.

## B10 — Layout, focus, feedback, accessibility

- Fixed overlay layout from the study: Drawing tools over Settings at left, Layers over Properties at right, Preferences centered. No dragging/docking. Headings remain reachable; each body scrolls. At crowded sizes, stack panels in scrollable side rails rather than moving camera bounds or overlaying unreachable controls.
- Minimum full-editor size: 800×600 logical px. Below it show a resize notice and retain safe Save/Close access; do not pretend the desktop layout supports mobile editing. Menu scaling is independent of drawing zoom. Hidden/minimized bodies leave focus traversal.
- Focus follows visible reading order. Selecting a layer keeps keyboard focus in Layers. Closing a panel returns focus to its opener or canvas. Menus/dialogs restore prior focus and do not replay the click beneath them.
- Status area shows active tool/prerequisites, selection count, and invalid construction reasons. Unsaved marker appears beside document title. Movement keeps green/red and adds valid/blocked cursor or accessible state feedback, not a mandatory error toast.
- Layers participation uses only the approved icon, with an accessible name; Properties keeps compact Active/Inactive. No status tooltip proliferation. Incomplete-parent Add tooltips use the approved text on hover and keyboard focus; wrong selection has its own message.
- View includes Fit drawing and Reset view. Fit uses committed Points/segments/circles and usable reference bounds, excludes previews, accounts for overlay gutters, and respects zoom limits. An empty drawing resets. Reset uses 100% with origin at viewport top-left. Controls remain keyboard accessible; full keyboard-only geometry authoring is explicitly outside this mouse-first slice, not a claimed accessibility certification.

## B11 — Reference images

### Records and importing

- ReferenceLayer owns id/name/properties and references ReferenceGeometry. Keep existing ReferenceProperties color, opaque image asset ID, and known_distance (metres, null or nonnegative). Color styles guide/handle feedback, not image pixels.
- ReferenceGeometry owns an anchor Point at world top-left, positive scale in metres per decoded image pixel, and optional calibration endpoints in image-local pixel coordinates. Its anchor is an authoritative geometry Point with local identity; no land layer shares it. Samples are image-local coordinates, not duplicated world Points. Asset metadata supplies normalized pixel width/height and content digest.
- Add Reference creates empty selected layer/Properties, retaining tool. Import PNG/JPEG/WebP; normalize orientation before establishing dimensions. Animated input uses the first decoded frame and is saved as a static supported image, with notice. No remote URLs, SVG scripts, rotation, crop, skew, or nonuniform scaling.
- First import fits within 80% of the visible viewport width/height, centered in world view without moving the camera. This is uncalibrated. Decode/prepare before commit; picker cancellation/failure leaves the layer unchanged.
- Replacement keeps layer ID/name/color/order, world center, and world width; derive new height from aspect ratio. Clear calibration line and known distance. No land geometry moves. Bind asynchronous requests to document/layer/request generation; switching/deleting the layer, leaving the document, Undo removing it, or a newer import invalidates stale completion.
- Limits: 20 MiB encoded and 40 megapixels per image; reject with a concrete explanation rather than silently downsampling. Bound decoded cache memory and evict unused textures; saved bytes remain intact.

### Tools and calibration

- Reference first-use Move. Move drags translation. Scale drags a corner about its opposite corner, preserving aspect ratio; forbid pivot crossing or zero/nonfinite scale. Both use read-only previews, commit once on valid release, and roll back on cancellation/invalid release. No Grid/Drawing snap or land endpoint attachment.
- Move preserves calibration. Manual Scale keeps local samples but clears known_distance, visibly becoming uncalibrated.
- Reference Line clicks two distinct locations inside the selected image. They are image-local samples, not land Points/segments. Completing a line replaces the old line and clears known distance in one action; cancelling preserves the old calibration.
- Enter/blur a positive known distance with a valid line: scale so sample length equals that distance, holding the first sample's world position fixed. Update anchor, scale, and known distance atomically. Positive distance without samples may be retained as unfinished input; a newly completed line clears it rather than accidentally applying an old distance.
- Null means unassigned; zero remains an unfinished setting. Neither changes transform, and both mark uncalibrated. Negative/nonfinite distances are invalid. An empty/missing-image Reference tool stays selected but inert.
- Image assignment/replacement, each completed move/scale, each reference-line replacement, and distance+calibration are individual history actions. Retain immutable old assets while history references them.

### Asset recovery

- Save image bytes inside the portable document, not transient object URLs or local path assumptions. Same-content relink restores a missing asset without changing transform/calibration. Different content follows replacement rules.
- Missing/corrupt assets retain land data, Reference records, transforms, samples, asset IDs, and any original bytes; show a placeholder and disable image tools. No silent removal/nulling on save. B13 distinguishes damaged images from structural document corruption.

## B12 — Area dimensions and generated planting layout

- Dimensions stay in Area.outline.dimensions, not menus/properties. Area.properties.planting_type selects Flat/Row/Mound. Flat remains empty. Preserve each type's committed settings when switching. Crop remains a nullable name, not a seed assignment.
- Row spacing and mound spacing mean clear edge-to-edge gap in metres. Row pitch is width+spacing; mound pitch diameter+spacing. Zero spacing allows touching. Width/diameter must be positive for generation; null or stored zero means unfinished settings and yields no generated output. Negative/nonfinite values are invalid. Row also requires direction; no hidden default for null.
- Row direction is its long axis: 0° right, clockwise positive in the downward-y canvas. Accept 0–360 inclusive; 360 renders as 0 without rewriting user data. Use an undirected axis for generation so opposite directions produce the same arrangement.
- Rows: project the boundary into the row-aligned frame, place the first strip's outer edge at its minimum perpendicular bound, then repeat by pitch and clip strips to the occupied region. A concave boundary may produce several pieces of one strip; these are derived planting footprints, not extra land boundaries. Drop zero-area remnants. Nominal width stays the setting even at clipped ends.
- Mounds: square axis-aligned lattice from minimum x/y bounds plus radius, repeating by pitch. Include only whole disks contained in the area; tangency allowed. Do not clip partial mounds or add stagger/rotation controls. No fitting features yields “No features fit,” not invalid land.
- Output is read-only derived data, not Geometry points/lines/circles/shapes or individual history actions. Regenerate after committed boundary/type/dimension or eligibility changes, load, and Undo/Redo, not camera/unit changes or transient drags. Save inputs, not derived copies. Inactive boundaries retain settings but show no generated output or contributions.
- Revision-key results by document, layer, boundary, parameters, and eligibility. Invalidate old output immediately; publish only the current revision. Failure/cancellation cannot leave stale output shown as current. Cap a generation request at 20,000 candidate strips/disks and ask for coarser dimensions rather than freezing or publishing partial geometry; use bounding estimates and incremental work.
- Later Plant contracts must define seed identity, suitability, capacity, yield, and schedules separately; do not attach durable seed data to regeneration indexes.
- Numerical soil fields keep existing nullable values as raw recorded laboratory observations in milestone 2. Label units/methods as unspecified, not validated for agronomic comparison; accept finite values or blank/null, perform no canvas-unit conversions, suitability scoring, or nutrient interpretation. Drainage is a categorical observation. Future soil comparisons require explicit unit/method/source metadata before being implemented, not guesses from these bare fields.

## B13 — Save, open, leave, and recovery

### Commands and drafts

- One controller command path handles menu/button/keyboard Save, Save As, and Save chosen on leaving. Intercept before blur handlers can mutate a draft incidentally.
- Direct Save/Save As first validates all ordinary property drafts in captured owner/units. If any is invalid, block the save and retain drafts with focus/error; otherwise commit valid changed values once. Unchanged values add no action. Preflight all drafts before committing any, so one invalid field does not partially settle a batch.
- Pending Rename or Preferences drafts block document Save until the user uses Save/Cancel or Apply/discard and retries. Never silently Save Rename or Apply Preferences. Apply changes workspace settings, not drawing history.
- Save serializes committed geometry, including standalone Points/open outlines/inactive descendants, not a dashed candidate or unfinished drag. Saving without leaving preserves the operation/preview context. It never completes a boundary.
- New/Open/Close with unsaved content or pending drafts offers Save/Discard/Cancel. Opening the confirmation changes neither content nor drafts. Save runs the same settlement path and leaves only on successful save; explicit drafts needing attention return to editing. Cancel preserves data, drafts, selection, and drawing context.
- Discard abandons changes/drafts only when the destination transition succeeds. Cancelling an Open picker or failing candidate validation retains the current drawing even after choosing Discard. No prompt is needed when both document and drafts are clean.
- Save failure/dialog cancellation causes no further document change. Ordinary edits deliberately committed during settlement remain committed and undoable; do not roll them back or mark them saved. This clarifies “keeps the drawing unchanged” as preservation of in-memory work, not reversal of accepted input settlement.
- New creates a new document identity/default settings. Close returns to the empty application shell; web Close is not a browser-tab close. Open loads into a detached candidate and swaps only after validation/successful leave handling.

### Storage and saved state

- Native: explicit Save/Save As to a portable .ggnome container. Save As creates a new document identity while preserving internal layer/geometry IDs; copy applied workspace settings and retain session history. If the destination step fails/cancels, do not change document identity/location.
- Web baseline: explicit Save to this browser, using an IndexedDB document/asset transaction. Open chooses a browser-saved drawing or Import file; Export file produces the same .ggnome container. Save As creates a new browser-library identity/name. Clearly label browser-local storage as not cloud backup. Export initiation alone is not proof a file was saved, so it does not clear a dirty state that browser Save has not persisted.
- Request persistent browser storage where available but handle denial/quota/private-mode errors. Keep in-memory data and unsaved state, offer retry/export, never suggest clearing storage. File System Access is an optional later enhancement, not the cross-browser baseline.
- Native writes use same-directory temporary output, completed-write readback/validation, then platform-safe replacement. Preserve the previous good file on failure. Detect an externally changed destination and require Save As or an explicit overwrite choice. Browser writes confirm transaction completion and read back the written revision before success. Do not claim saved on an initiated write.
- Capture an immutable revision for saving. Mark only that snapshot saved; edits made afterward remain dirty. Dirty comparison covers user content, not allocator high-water bookkeeping, selection, camera, or history position. Returning to saved content via Undo/Redo clears the indicator even if counters increased. Explicit Save persists high-water marks; workspace metadata also retains local maxima.
- Persist applied appearance/navigation settings, camera, and non-property panel states separately by document ID. Reopen with empty history, no selection/snap target, closed Properties, Point → Move, and no tool-function memory/drafts. No autosave or crash recovery is implied.

### Portable structure and load

- .ggnome is ZIP containing document.json plus optional assets/ entries. JSON schema_version starts at 1, with format: garden-gnome, document_id, canvas_size, ordered layer IDs/parent links, geometry registry, name/ID high-water counters, and asset manifest. Use tagged GeometryRef values for external geometry references. Images address immutable asset IDs with SHA-256 digest and decoded dimensions; manifest paths are relative assets/ entries, never absolute or traversing paths.
- Runtime objects remain reference-based. Serialize each layer and Geometry once in keyed registries; layers contain outline geometry IDs and ordered child IDs, not recursively copied geometry. Local segments refer to local Point IDs; ClosedShape refers to segment IDs plus traversal direction. No duplicate saved calculated Active flags, previews, selections, generated rows, or history.
- Structurally validate supported schema/features, unique IDs, owner/type references, hierarchy acyclicity and exclusive ownership, order membership, counters at least the saved maxima, finite values, enums, bounds, and asset sizes before swapping. Reject dangling references, duplicate IDs, unsupported versions/features, and unsafe ZIP entries. Do not silently repair/merge/prune a document.
- Derive topology/completeness/participation from saved records. Open outlines and closed inactive descendants are legitimate. Reject a complete cycle/circle that violates own geometry or valid-parent/sibling requirements rather than silently importing a changed land region. Missing image bytes are a recoverable asset warning, not a reason to throw away valid land data.
- Container safety bounds: 100 MiB compressed, 256 MiB total uncompressed, 16 MiB document.json, 100 image assets, plus B11 per-image limits. Reject duplicate entries/path traversal and decompression beyond declared limits. Do not execute or retrieve resources referenced by imported files.
- Broken/missing image assets open as placeholders; keep their descriptors and available bytes on re-save with an explicit warning. Relink/remove is intentional and undoable. Unsupported newer feature kinds block opening to prevent lossy re-save. There is no legacy migration from the JS prototype because it has no saved-document format.

### Platform limits

- Application-controlled New/Open/Close uses the full confirmation contract. Browser tab close/reload/external navigation can show only the browser's generic warning, after user interaction, and it is not guaranteed. Register it only for dirty data/drafts. Do not promise custom Save/Discard/Cancel or asynchronous saving during browser termination.
- Forced process termination/crashes can lose unsaved work on native too. No automatic recovery snapshots are added under the guise of workspace preferences. These are platform boundaries, not a change to the app-controlled leave flow.

## B14 — ActionsBuffer and preview recovery

### Actions and capacity

- Store action-specific immutable recovery records, not pointer events. An action carries geometry/property changes, stable identity/ownership, before/after values or deleted records, and eligible operation context. Undo executes an inverse and moves recovery information to Redo only after successful atomic application; Redo restores the original identities. PlacePoint/RemovePoint are illustrative inverse types, not simulated tool clicks.
- Group as one action: standalone Point placement; new endpoint+segment; existing-Point join connection only; insertion+segment split; one completed point/segment/group movement; Point deletion with incident segments/dependent circles; direct segment deletion; selected-set deletion; whole-layer subtree deletion; empty-layer creation; each committed property edit (Rename on Save); Fill change; completed Circle creation/resize/delete; image assignment/replacement/move/scale/reference-line/calibration. Generated output has no entries beyond its input edits.
- Rejected/no-op edits, unchanged values/moves, Escape/Enter, preview updates, pan/zoom, selection, tool/panel changes, and Preferences create no drawing-history action and do not invalidate Redo. A new committed edit after Undo clears Redo.
- Default 50 action groups; Preferences accepts integers 1–1,000, counting Undo+Redo together. Transfer is not duplication. New overflow evicts oldest undoable history, not geometry. Applied capacity reduction trims oldest Undo entries first, then furthest-future Redo entries, preserving the next redoable steps. Increasing capacity cannot resurrect evicted entries.
- Retain old immutable assets while document/history references them. Asset cleanup considers both sides of history, open saves, and current document; never delete data needed by an inverse.

### State restoration

- History is session-only: Save preserves it; reopening starts empty. Keep the content-based saved marker independent of buffer index/counters.
- Undo/Redo keeps surviving current selection, clears references to removed items, and does not auto-select restored objects or resurrect an old snap target. Counters never rewind. Restoration order must preserve dependencies, ownership, boundary membership, properties, and derived eligibility together.
- Failed replay leaves document/history unchanged, shows a brief failure notice, and does not skip the entry. Pre-replay cancellation of a transient candidate remains separate. Empty-history controls are disabled; a canvas shortcut may still clear a transient candidate without changing document content.
- Field-local Undo/Redo never falls through to drawing history. Drawing-history controls are gated by unapplied property drafts under B09.

### Live Line context

- Canvas.preview holds the selected tool's Preview object (PreviewPoint, PreviewLine, etc.) or null, distinct from active_operation. CanvasController updates candidate/validity; painting directly calls only the current Preview's read-only drawing method. No callback registry or paint-time scanning of ActionsBuffer.
- active_operation holds target/tool/function, a transient operation token, current anchor and starting data. Actions record eligible before/after Line context, but the live anchor survives history eviction independently of the buffer. Token representation is an internal detail, not saved document data.
- During the same uninterrupted Line operation, Undo A–B removes B/segment and resumes the dashed preview from A. Undoing newly placed A removes it, leaving Line selected awaiting a start; keep replay eligibility so immediate Redo can restore A/preview. Reused starting Points are not new geometry actions and are never removed by cancelling the start.
- Redo restores the relevant starting preview, next anchor if drawing was ongoing, or completed state without a trailing preview. Completion can retain the latest operation token for immediate Undo until a new operation/explicit cancellation/context switch starts; it does not keep a visible trailing candidate.
- Switching tool/function/layer, explicit Enter/Escape, pointer-capture loss, document transition, or starting another operation invalidates prior context eligibility. History still restores geometry but cannot revive the old drawing operation after returning. Same-tool/function reselection, pan/zoom between clicks, and Save do not invalidate it. Unrelated committed document edits end the live operation before applying; this avoids replaying a property action into a stale geometry context.
- Other tool Undo/Redo clears the candidate and starts fresh unless a future explicit contract grants continuation. Preview objects/candidates are not independently saved or undone; line context recovery is limited metadata attached to geometry actions.

## B15 — Complete user journeys

### W01 — First field

Start a new document: no selection, Point → Move, default view. Add Field creates Field 1, selects it, and opens Properties without drawing. Choose Line → Draw and click A, B, C: each placement is committed; a dashed preview follows from the last anchor. Hover A for the outer ring/union cue and click to close. A valid loop automatically becomes the field boundary and Active; Add Plot becomes available. If closure crosses an edge, retain only the rejected candidate/reason; prior placements remain. Move to a valid endpoint or Escape and use explicit tools. Switching to Point keeps the committed open path. Save can retain it as inactive geometry without inventing a closing edge.

### W02 — Plot and area containment

Select a completed Field, Add Plot, and draw inside it. Shared edges/vertices are permitted; crossing outside a concave parent or overlapping a sibling interior is rejected. An incomplete Field cannot receive a new Plot, even if another Field is valid. Complete the Plot, select it, Add Area, and draw the same way. Names/IDs and selected parent are independent. Deleting a parent boundary segment preserves its Points/children but marks the subtree inactive; children show hatch if closed and cannot be edited until the parent is repaired around them. An invalid attempted parent move leaves children and original geometry unchanged.

### W03 — Area settings, units, and layout

In milestone 4, select a valid Area and switch from Flat to Row. Enter width, clear gap, and direction; valid drafts commit once and generate clipped strips. Missing/zero width produces no output but does not invalidate land. A feet-to-metres display switch commits a valid length in its original units first; invalid input blocks conversion until Revert/correction. Change to Mound after settling outgoing fields; Row settings stay stored. Enter positive diameter and gap; only fully fitting disks appear. Undo a setting restores its previous input and regenerates, not thousands of individual marks. Reopen the parent: keep dimensions and crop data but suppress generation and downstream participation. Repair restores current valid output.

### W04 — Selection, editing, deletion, history

Select the layer in Layers. Point → Move clicks a Point; Line → Move clicks an edge or polygon interior. At overlapping hits, category/distance/ID rules choose consistently. Shift-click creates a layer-local group; drag a selected item to translate distinct defining Points once. Connected edges preview dotted; invalid release returns the entire edit to its start. Point → Place near a segment projects and splits; Point Delete removes that Point and its attached segments without reconnection. Undo restores the split state; Undo again restores the original unsplit segment identity. A Line A–B Undo returns the dashed preview to A only in that same live operation. Switch tools and return: retained geometry is reusable, but the old operation never resumes. Empty history and unapplied property drafts gate drawing Undo/Redo as documented.

### W05 — Circle and reference tracing

In milestone 2, use a circle tool on a layer without surviving boundary segments: center/circumference or opposite diameter ends. First-click cancellation leaves no circle or new center. Valid completion creates one circular boundary; Move its center or Resize with live constraints. Fill changes its effective pattern without changing region semantics. In milestone 3, Add Reference, import a supported image, and see an uncalibrated fit. Reference Line picks two image samples; enter their real distance to scale about the first sample. Trace land in a separately selected layer; no cross-layer point ownership is created. Moving the image preserves calibration and never moves land. Manual scaling clears known distance. Replacement decodes before commitment, preserves center/width, clears calibration, and is one Undo action. Late/cancelled loads cannot overwrite another layer. Missing images on reopen show placeholders without discarding traced land.

### W06 — Drafts, save, leave, reopen

Edit a normal property and minimize: valid text commits; invalid text remains available when expanded. Switch layers: valid ordinary input settles to the old owner, invalid/rename drafts are discarded under the existing explicit transition rule. A units change instead blocks on invalid length text. Opening layer-deletion confirmation commits nothing; Cancel returns exact drafts, Confirm deletes committed records and drops their drafts.

Use Save by button or shortcut: both preflight drafts, require explicit Rename/Preferences settlement, commit valid ordinary edits, and serialize the same captured content revision. A dashed Line candidate is not serialized and may remain after save. New/Open/Close with dirty content or drafts offers Save/Discard/Cancel. Cancel restores editing untouched; Save failure retains work/dirty state; Discard takes effect only after destination success. A corrupt Open leaves the current drawing intact. Native saves write verified portable containers; browser Save writes verified local storage, with Export for portability. Reopen restores committed geometry and applied settings/view, recalculates validity, starts empty history/no selection/Point Move, and restores no drafts. Unsupported document structures fail clearly; missing image assets get placeholders. Browser-controlled exit has only its generic warning and no guaranteed crash recovery.

## B16 — Flutter execution handoff

### Architecture and modules

Create the Flutter application in flutter/ so existing Node skeletons, tests, icons, and HTML study remain intact. Start with pure-Dart model/geometry/validation, typed references and inverse actions, not widget-owned geometry. Organize lib/domain, lib/application, lib/presentation, and lib/persistence with platform adapters; keep ownership uniform across Field/Plot/Area.

Canvas owns document references, CanvasControl, CanvasDisplay, and nullable Preview. CanvasController orchestrates commands and publishes completed transactions. Use ordinary Flutter notifier/listenable state and immutable operation results first; no dependency on a large state-management framework. Domain code must not import widgets, perform I/O, or mutate during painting. One shared transform serves paint/input/hit/snap. Scene and overlay painters remain read-only.

Use a persistence interface for native file and browser IndexedDB adapters, a versioned codec with detached-load validation, immutable asset store, and separately keyed workspace metadata. Candidate package families: Flutter file_selector for native pickers/browser import, archive for ZIP, a UUID implementation, cryptographic digests, and browser interop for IndexedDB. Verify APIs/license/platform support against the inspected SDK before adding/pinning dependencies; exact versions are engineering work. Do not pretend web native save-path APIs exist.

### Implementation order after authorization

1. Establish flutter/ scaffolding and Linux/web builds, record actual toolchain/target commands, integrate existing icon assets without changing the prototype. Implement references, counters, one authoritative boundary, units, topology and validation with application-code tests.
2. Build CanvasControl/controller, camera transforms, grid, fixed overlays, layer creation/selection, Point/Line tools, previews, and first complete Field→Plot→Area journey. Add history transaction boundaries as commands are introduced, not retrofitted after tools.
3. Add multi-selection, connected movement/deletion, properties/drafts/focus, full ActionsBuffer/Line context, and invalidity participation/presentation.
4. Add portable codec, native/browser save/open, workspace settings, leave handling, malformed-document rejection, and saved-state tracking. Exercise failure/cancellation and complete milestone 1 on native/web before calling it usable.
5. Add circle creation/editing, decorative Fill, extended recorded properties and their history/serialization. Then images/calibration/assets; then planting settings/generation. Complete W05/W03 at their stage rather than exposing unfinished controls.

### Verification and budgets for application code

- Repository currently has package.json/Node model tests and an HTML study, not a Flutter application. The planning environment has Flutter 3.38.9 stable and Dart 3.10.8 available; this is an observed installed toolchain, not a latest-version claim or a successful app build. Chrome and Linux are available. SDK upgrades, flutter doctor/toolchain setup, and package pinning happen only in the implementation phase.
- Intended commands once flutter/ exists: flutter pub get, dart format --output=none --set-exit-if-changed lib test, flutter analyze, flutter test, flutter build linux, flutter build web. Exercise real desktop/web user journeys and persistence beyond unit tests. Use npm test for existing JS code only if that code is touched or as an integration baseline, not for documentation edits.
- Test domain boundary predicates, identity/reference integrity, compound Undo/Redo, unit drafts, topology insertion/deletion, serialization round-trips/malformed input, storage failure/asset lifetime, asynchronous stale-result protection, real component input routing, and target-device workflows. No docs test suite is introduced.
- Initial benchmark workload: 200 land layers and 10,000 combined Points/segments, nested descendants, and overlapping viewport content. Engineering targets, not measured claims: ordinary feedback within 100 ms; p95 frame work within a 60 Hz frame budget during navigation; geometry-only save/open within two seconds on the named reference machine. Record hardware/build mode/data with results and report any missed budget rather than fabricating compliance.
- Image/generation limits are B11–B13. Bound render caches, use viewport culling/spatial indexes, and perform incremental cancellable large work. Do not assume native isolates work identically on web; evaluate workers only if profiling requires them. No silent partial generation or data loss as a performance workaround.
- The remaining gate is user authorization to implement, followed by real builds/tests/device evidence. No product question in the agreed Build scope blocks the handoff. Any discovered need to reverse a major ownership, persistence, or interaction contract must be raised rather than hidden in implementation.

### Platform references

- [Browser beforeunload limits](https://developer.mozilla.org/en-US/docs/Web/API/Window/beforeunload_event): generic browser copy, interaction requirement, unreliable termination delivery.
- [Flutter file_selector platform support](https://pub.dev/packages/file_selector): native save-location API is not available on web; browser import is supported.
- [Browser storage limits](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API/Storage_quotas_and_eviction_criteria): local saves require explicit quota/failure handling and are not cloud backup.

The entries below preserve the original discussion. They include superseded proposals, earlier open questions, and previous status labels. Only B01–B16 above govern the handoff; these entries do not reopen decisions.

## Historical decision log

Earlier whole-line draft and Enter-versus-Escape descriptions below are historical; the approved per-placement contract above supersedes them. Earlier embedded geometry examples are superseded by reference-based ownership.

### B01 — Delivery direction, primary input, and first milestone

- Status: core scope approved; B02 is current. Remaining subfeature placement is tracked in the scope matrix.
- Approved rule: prepare the full Build workflow and implement it in stages, starting with a usable boundary editor.
- Approved platforms: native desktop and web.
- Approved primary input: mouse and keyboard. Additional interaction methods are deferred.
- Reason/example: the first milestone must support actual boundary editing, not just navigation of a prepopulated scene; later Build capabilities stay in the workthrough.
- Superseded rule: none. This establishes scope for the new Flutter work; it does not change the earlier canvas plan's documentation-only scope.
- Approved first milestone: fields/plots/areas; closed straight-edged boundaries; boundary-point selection, movement, and deletion; containment and overlap validation; pan/zoom, units, and basic properties; undo/redo; save/reopen.
- Approved later slices: circle tools, reference-image calibration, and generated rows/mounds. Their documentation is completed before implementation begins.
- Canonical documentation: Canvas guide, First Flutter milestone section.
- Remaining decisions: milestone placement of multi-selection, fill, row/mound settings, and soil entry; exact basic property set; concrete OS/browser verification targets. No new geometry or recovery semantics were approved by this scope decision.
- Next discussion: B02 identity and ownership.

### B02 — Identity and ownership

- Status: subtopic resolved; creation and lifecycle remain open.
- Approved rule: stable workspace-unique layer IDs across layer types; names are separate; exactly one owning field per plot and one owning plot per area; no shared child objects; rename preserves identity and relationships; initial sibling order follows creation order.
- Reason/example: renaming Vegetables to Kitchen garden leaves its areas attached and geometry references unchanged.
- Superseded rule: the Field/Plot/Area ID descriptions now state workspace uniqueness and permanence in addition to caller-supplied identity. The JS skeleton's permissive membership behavior is not carried forward as the Flutter contract.
- Canonical documentation updated: Canvas layer ownership contract, Layers guide, and Field/Plot/Area ID descriptions.
- Remaining decisions: ID allocation/serialized reference representation, creation defaults/flow, parent prerequisites, deletion, visibility/locking, manual reordering, and hit priority in their owning issues.
- Next discussion: B02 Add Field/Plot/Area flow.

### B02 — Creation flow

- Status: subtopic resolved; defaults, parent-boundary prerequisites, and lifecycle remain open.
- Approved rule: Add Field/Plot/Area live in Layers; Field needs no selection, Plot needs its field selected, Area needs its plot selected; create an empty layer, select it, and expand Properties through the existing layer-switch rules; retain the active tool and do not start drawing automatically; cancelling unfinished drawing does not delete the layer.
- Reason/example: select a field → Add Plot → empty plot selected → optionally rename → choose Line and draw. Cancelling that first drawing leaves the plot available for another attempt.
- Superseded rule: none; this completes previously unspecified creation behavior. No automatic tool change or boundary wizard is introduced.
- Canonical documentation updated: Layers guide, Canvas Adding land layers contract, and CanvasController action table.
- Remaining decisions: default names/properties, completed-parent prerequisites, deletion/visibility/locking, and manual reordering.
- Next discussion: B02 creation defaults.

### B02 — Creation defaults

- Status: defaults subtopic approved and documented; parent prerequisites and lifecycle remain open.
- Approved rule: names use separate workspace-wide Field/Plot/Area sequences starting at 1, without recycling numbers after rename/deletion; use fresh documented defaults, not inherited or last-used values; new areas start Flat, with no crop and unset row/mound measurements; outlines remain empty with zero geometry counters.
- Reason/example: a new plot under another field continues the Plot sequence but does not copy that field's or another plot's appearance or geometry.
- Superseded rule: AreaProperties previously required planting_type without specifying an initial choice; its creation default is now flat. Existing examples showing intentionally selected Row remain valid.
- Canonical documentation updated: Layers guide, Canvas Creation defaults contract, and AreaProperties shape/attribute description.
- Remaining decisions: parent prerequisites, lifecycle, and detailed manual-name collision/persistence/history handling. Property defaults do not settle first-milestone control placement.
- Next discussion: B02 parent-boundary prerequisites.

### B02 — Completed parents before child editing

- Status: geometry editing prerequisite approved; Add eligibility needs clarification.
- Approved rule: a parent boundary must be complete before child geometry can be drawn or edited. A plot cannot be drawn within an incomplete field boundary; an area likewise requires a completed plot boundary.
- Reason/example: an unfinished field outline cannot provide the boundary against which plot drawing is checked.
- Canonical documentation updated: Layers guide and Canvas Parent boundaries and child editing contract.
- Remaining decisions: whether to block adding empty children as well; non-geometric edits if empty children are allowed; parent replacement/edit lifecycle in B03/B04.
- Next discussion: Add eligibility versus geometry editing eligibility.

### B02 — Completed parents before Add, with tooltips

- Status: creation prerequisite and incomplete-parent hover feedback resolved.
- Approved rule: do not add plots/areas without completed field boundaries, or areas without completed plot boundaries. Apply this to the actual selected parent and its owning hierarchy; retain the existing selected-parent requirements.
- Approved feedback: a small hover tooltip, `complete field before adding new plot`, and the corresponding area message, `complete plot before adding new area`. Disabled controls must still expose the hover explanation.
- Superseded proposal: allowing empty children under incomplete parents is rejected. The earlier Add-eligibility question is closed.
- Canonical documentation updated: Layers guide, Canvas creation/editing contracts, and controller action table. Field/Plot examples no longer show children beneath empty parent outlines.
- Remaining decisions: later parent edits with existing children in B03/B04; keyboard/wrong-selection feedback in B10; layer deletion and other lifecycle controls next.
- Next discussion: B02 deletion and descendant handling.

### B02 — Layer deletion

- Status: deletion flow resolved; visibility/locking/reordering scope remains open.
- Approved rule: Delete acts on the selected layer from Layers and requires confirmation identifying affected descendants. Delete a field with all its plots/areas or a plot with all its areas, atomically and without orphans. Cancel leaves the document unchanged.
- Approved recovery: the entire deletion is one undoable action; Undo restores identities, geometry, properties, and ownership. Detailed selection/history restoration remains in B14.
- Approved cleanup: clear affected selection, previews, Properties, and snap targets; retain the active tool; do not automatically select a replacement; preserve unaffected state.
- Canonical documentation updated: Layers guide, Canvas Deleting layers contract, selection rules, and controller action table.
- Remaining decisions: draft/focus handling around confirmation in B09; detailed history behavior in B14; point/line deletion in B07; visibility/locking/reordering scope next.
- Next discussion: B02 visibility/locking/reordering scope.

### B02 — Layer-control scope and closure

- Status: resolved for first-milestone layer behavior; B03 is current.
- Approved rule: no per-layer hide toggle, layer locking, or manual sibling reordering in the first milestone. Land layers stay visible and unlocked, subject to selection/validity rules, with siblings in creation order. Workspace panels may still be hidden.
- Deferred scope: these layer controls may be considered for later milestones; no later delivery or behavior is promised by this decision.
- Canonical documentation updated: Layers guide and Canvas layer ownership/control contracts.
- Remaining cross-cutting work: assigned explicitly in B02 closure and handoff; none is claimed implemented or tested.
- Next discussion: B03 single authoritative boundary per land layer.

### B03 — One closed region per land layer

- Status: single-boundary model approved; completion/designation and replacement remain open.
- Approved rule: each completed Field, Plot, and Area is one closed region with one authoritative boundary. Use polygon boundaries first and allow a single circle boundary with the later circle tools. Unclosed construction geometry does not itself define occupied land.
- Deferred scope: grouping and several disconnected regions in a single layer; holes remain deferred under the earlier agreement. This does not remove B05 geometry multi-selection.
- Reason/example: two disconnected growing beds are two Area layers, not one area with two boundaries. Their parent plot has its own single boundary.
- Canonical documentation updated: Layers guide, Geometry land-boundary contract, and the Field geometry example, which now contains one closed polygon without an additional circle.
- Remaining decisions: designation/completion, construction geometry storage, and edit/replace lifecycle; exact validity and gestures remain in B04/B06.
- Next discussion: B03 automatic boundary designation on valid completion.

### B03 — Automatic boundary completion

- Status: initial completion flow resolved; edit/replace lifecycle remains open.
- Approved rule: the first valid closed loop automatically becomes the layer's authoritative boundary after validation, with no separate designation command. Closure alone is insufficient. Invalid multi-step completion retains its preview and explains the failure while leaving the layer incomplete.
- Approved completed-layer behavior: edit the existing boundary; another independent region requires another layer. Replacement must be explicit, with its detailed flow still to be decided.
- Reason/example: finish a valid field outline → the field is complete → Add Plot becomes available while that field remains selected.
- Canonical documentation updated: Layers guide, Geometry boundary-completion contract, and CanvasController completion action.
- Remaining decisions: edit/replace lifecycle, construction geometry, and concrete boundary reference; detailed validity and gestures in B04/B06.
- Next discussion: B03 editing/replacing completed boundaries while preserving children.

### B03 — In-place editing and connected-edge previews

- Status: preview and placement-validation behavior approved; B03 remains open for storage/construction and connected-edit details.
- Approved rule: point and segment edits show dotted previews of the attached edges leading to the proposed position/endpoints. Validate the connected change when the piece is placed; use the existing commit, invalid-drag, and cancellation rules.
- Scope correction: no separate Replace boundary action. Earlier decision-log references to explicit replacement and an unresolved replacement lifecycle are historical and superseded by this decision.
- Display distinction: connected-edge previews show proposed geometry even when snapping is off; they are not snapping alignment guides or saved lines.
- Canonical documentation updated: Geometry boundary completion/editing, unfinished drawing, and implementation-plan preview/snapping rules.
- Still open: exact segment movement and tool/gesture, boundary reference, construction geometry, and B04 parent/descendant validity. The preceding proposal about fixed children is not approved by this answer.
- Next discussion: whether moving a segment translates both endpoints together, retaining its length and direction while neighboring edges adjust.

### B03 — Segment translation

- Status: segment-movement behavior approved; the previous entry's open movement question is resolved.
- Approved rule: dragging a segment moves both endpoints by the same distance and direction, preserving its length and angle while neighboring edges adjust. Moving an individual endpoint can change the segment's length or angle.
- Canonical documentation updated: Geometry in-place editing and implementation-plan preview rules.
- Still open: edit tool/gesture, segment snapping-anchor choice, boundary reference, construction geometry, and B04 parent/descendant validity.
- Next discussion: keep children fixed during parent boundary edits and reject placements that would invalidate their containment; this remains a proposal, not an approved rule.

### B03/B04 — Live move validity and fixed children

- Status: parent-edit handling and live green/red move feedback approved.
- Approved rule: keep children fixed during parent edits and reject placements that would invalidate descendant containment. Validate point/segment moves in flight: green for valid, red for invalid. Continue showing dotted connected-edge previews; red candidates cannot commit.
- Release behavior: validate the final candidate; commit a valid connected change once. An invalid release returns to the original position, not the last valid preview position, without requiring an error notification.
- Superseded wording: earlier requirements to explain rejected boundary moves through a notification and earlier open parent-edit questions are historical. Initial multi-step completion still retains an invalid preview and explains its failure; this approval does not redesign that flow.
- Canonical documentation updated: Geometry editing, unfinished drawing/controller feedback, and implementation-plan rules/checks.
- Remaining decisions: touching and other B04 validity details; B03 boundary storage/construction; edit gestures, snapping anchors, and accessible non-color feedback in their owning issues.
- Next discussion: whether children may touch their parent boundary and sibling boundaries may share points or edges without overlapping interiors.

### B04 — Boundary touching

- Status: parent/child and sibling touching approved; earlier open touching questions are resolved.
- Approved rule: child boundaries may lie on parent boundaries, and siblings may meet at points or share edges without requiring gaps. Touching does not count as interior overlap; children still cannot extend outside their parent.
- Scope at that time: preserve the existing Field/Plot non-overlap rules. Later decisions prohibit sibling Area interior overlap and limit endpoint joining to the selected drawing layer without cross-layer shared points.
- Canonical documentation updated: Layers guide, Geometry containment/contact contract, and implementation-plan validity rules.
- Next discussion: whether sibling Area interiors may overlap.

### B04 — Area interior non-overlap

- Status: Area interior overlap prohibited; earlier open Area-overlap questions are resolved.
- Approved rule: sibling areas may touch at boundary points or edges, but may not share interior land. Partial overlap, full containment by a sibling, and duplicate regions all violate this rule; containment by the parent plot remains required.
- Feedback: use live red move feedback and original-position restoration on invalid release; retain invalid initial drawing for correction under its separate completion rule.
- Canonical documentation updated: Layers guide/table, Geometry containment/contact contract, and implementation-plan validity rules.
- Next discussion: self-contact within one boundary and remaining crossing/degeneracy cases.

### B04 — No boundary self-contact

- Status: self-contact rule approved; the preceding self-contact question is resolved.
- Approved rule: a single boundary cannot pinch together or have nonadjacent segments meet at an extra point. Ordinary consecutive-segment joins and final closure remain valid. Touching between separate regions remains allowed.
- Feedback: use live red move feedback and original-position restoration on invalid release; retain invalid initial drawing for correction under its existing completion rule.
- Canonical documentation updated: Geometry land-boundary and ClosedShape contracts, plus implementation-plan validity rules/checks.
- Next discussion: collapsed edges and points placed along a straight boundary edge; tolerance and remaining construction-line crossing scope stay open.

### B04/B06/B07 — Subdivision and deletion without reconnection

- Status: collapsed-edge/straight-line vertex distinction approved; automatic splitting on point insertion and incomplete boundaries after point deletion approved.
- Approved rules: reject collapsing adjacent points during movement; retain collinear editable points; subdivide a segment when inserting a point; delete a point and incident segments without reconnecting its neighbors. The remaining outline stays incomplete until valid closure.
- Lifecycle distinction: explicit deletion may produce an incomplete outline; the valid-placement requirement for movement must not reject that deletion or restore the old boundary. Cancelling a later repair does not undo the deletion.
- Canonical documentation updated: tool descriptions, boundary lifecycle/point editing, Line and ClosedShape contracts, controller actions, and implementation-plan rules/checks.
- Still open: parent deletion/reopening with children, insertion/repair gestures, Line/ClosedShape storage and identities, branching, history, and persistence.
- Next discussion: preserve existing children but suspend their geometry editing/additions while the parent is incomplete, then require valid reclosure around them; this is a proposal, not an approval.

### B04/B07/B10/B12 — Inherited invalidity and participation

- Status: parent reopening with retained children approved; visible validity marking and active-only participation approved across Build and later Plant/Harvest calculations.
- Approved rule: active requires a valid own committed boundary and valid ancestors. Invalid parents deactivate descendants without deleting their geometry/data. Inactive boundaries cannot receive seeds or participate in boundary-based operations, yields, harvest windows, or totals. Selection does not affect this eligibility.
- Recovery: permit inspection and repair of the invalid boundary when its ancestors are valid; retain descendant geometry, validate parent reclosure around it, and reevaluate activity down the hierarchy. Parent recovery does not activate a child whose own boundary remains invalid.
- Preview distinction: temporary red move candidates do not invalidate previously committed active geometry. Committed reopening does.
- Canonical documentation updated: parent prerequisites, boundary validity/lifecycle, controller deletion, Plant/Harvest participation, and implementation-plan rules/checks.
- Remaining: validity-marker presentation in B10, detailed calculation refresh/cache behavior, storage/load/history mechanics, and remaining geometry contracts.
- Next discussion: a visible Layers status marker with a reason identifying the invalid boundary or blocking ancestor.

### B10 — Icon and hatched invalid interiors

- Status: validity appearance approved; the previous status-tooltip/Properties-reason proposal is superseded.
- Approved rule: use a Layers icon without status tooltip/text clutter, and render invalid interiors light grey with an angled hatch. This includes closed descendants invalid through ancestry.
- Display only: preserve saved geometry/colors/patterns; normal rendering returns when active. Keep persistent invalid styling separate from green/red move previews.
- Canonical documentation updated: Layers guide, boundary validity/appearance, and implementation-plan rules/checks.
- Next discussion: for incomplete outlines, use the icon and remaining open edges without inventing a closing edge or filled region; closed inactive children would still receive the hatch. This is a proposal, not an approved fill rule.

### B10 — Open outlines and Properties status

- Status: open-outline treatment approved; a compact Properties status is restored.
- Approved rendering: show remaining open edges and the Layers icon without any filled region, artificial closure, or retained old footprint. Closed inactive children continue to show the grey angled hatch.
- Approved Properties notice: read-only Active/Inactive near the top of Field/Plot/Area Properties, derived from the selected boundary and its ancestors. Keep Layers icon-only and do not restore status tooltips or long reason text.
- Superseded wording: the earlier prohibition on a Properties notice and the open-outline fill question are historical. This approval does not add a manual activation control.
- Canonical documentation updated: validity/appearance, Properties panel behavior, and implementation-plan rules/checks.
- Next discussion: direct segment deletion in B07; removing only the connection while retaining endpoints and leaving the boundary incomplete is a proposal, not yet approved.

### B07 — Direct segment deletion

- Status: segment deletion approved; the preceding segment-deletion proposal is resolved.
- Approved rule: remove only the targeted segment, keep its endpoints and other connections, and do not reconnect or automatically remove isolated points. A completed boundary becomes incomplete under the existing inactivity, rendering, and repair rules.
- Canonical documentation updated: segment-deletion contract, controller actions, Line behavior, and implementation-plan rules/checks.
- Next discussion: repair using existing endpoints and ordinary Line Join/Draw tools without a separate repair mode; exact input sequence remains a proposal to discuss.

### B06/B07 — Ordinary repair and endpoint join feedback

- Status: no separate repair mode and ordinary Line Join/Draw repair approved; Line endpoint feedback approved.
- Approved flow: reuse existing endpoints, using Line Join for a direct connection or Line for a path with new corners. Hovering a start endpoint shows a small outer circle; hovering the endpoint to connect while drawing shows the circle again and a union icon beside the pointer.
- Scope at this decision: these are temporary attachment cues, not geometry or a Boolean union. Final closure still validates before completion and reactivation. Hit/input behavior remains open; the later B08 decision below resolves snapping-switch independence.
- Canonical documentation updated: tool descriptions, boundary joining/repair contract, and implementation-plan rules/checks.
- Next discussion at that time: keep endpoint joining available independently of Grid/Drawing snapping; approved in the B08 entry below.

### B08 — Endpoint joining independent of snapping

- Approved: endpoint joining is separate from snapping. Turning Grid/Drawing snapping off leaves endpoint attachment and its outer ring/union cursor cues available; alignment alone does not create a connection.
- Updated B06/B08, the canonical snapping/joining contracts, and implementation-plan rules/checks.
- Next discussion at that time: endpoint acquisition tolerance and competing target priority; the targeting rule is approved below, with numeric radius and tie-breaking still open.

### B08 — Endpoint target acquisition and snapping priority

- Approved: a small fixed screen-space range; choose and highlight only the nearest eligible endpoint; the highlighted endpoint takes priority over grid/alignment snapping so preview and accepted connection agree.
- Updated B06/B08, canonical snapping/joining documentation, and implementation-plan rules/checks.
- Next discussion at that time: which layer's endpoints may be joined; resolved below. Numeric radius, equal-distance tie-breaking, and edge-interior target priority remain open.

### B05/B06 — Selected-layer-only joins

- Approved: joins target only the selected drawing layer, not nearby or coincident endpoints belonging to other layers. Contact does not share point identities or couple edits across layers.
- Terminology: “selected/active” here is the editing destination, distinct from Active/Inactive participation. Preserve repair of an incomplete selected layer and the existing prohibition on descendant editing beneath an invalid ancestor.
- Updated the selection/joining contracts and implementation plan.
- Next discussion at that time: Line click sequence for start, corners, endpoint finish, and cancellation; approved below.

### B06 — Line click sequence

- Approved: click a start, click empty positions for corners, and click a highlighted endpoint to finish. Returning to the starting point closes the loop. Keep a following preview, validate before commitment, retain invalid completion for correction, and use Escape to discard only the unfinished line.
- Updated the canonical Line flow and implementation plan.
- Next discussion at that time: finishing an open line without an endpoint join; approved below. Correction gestures and post-finish state remain open.

### B06 — Enter finishes open geometry; Escape cancels

- Approved: Enter finishes at the last clicked point after applicable validation, keeps the placed segments, and discards the trailing pointer preview without adding closure. The open boundary remains incomplete/Inactive until closed later. Escape instead discards the unfinished operation.
- Updated the Line contract, committed-incomplete lifecycle, persistence checklist, and implementation plan.
- Next discussion at that time: correction within the line preview; rejected in favor of explicit tool functions below. Minimum input for Enter and post-finish state remain open.

### B06/B07 — Explicit functions instead of correction steps

- User rejected Backspace preview-step correction. Use Escape to cancel the current unfinished line and selectable point/segment draw/delete functions to work on geometry; retain Point Move and place the joining function under Line as Join.
- Preserve the established click sequence, Enter finish, deletion semantics, and document Undo/Redo scope. Cancellation discards preview geometry rather than turning it into deletable committed data.
- Updated the tool catalog, governing contracts, completion walkthrough, and implementation plan.
- Next discussion at that time: direct deletion behavior; now approved as hover-highlight, click-delete, and retain the function.

### B06/B07 — Direct deletion and lighter documentation workflow

- Approved: choose Point Delete or Line Delete, hover to highlight the target, and click to delete; keep the function selected for repeated use. Existing deletion semantics remain unchanged.
- Keep behavior notes and walkthroughs, not documentation test cases or checklists. Stop creating or running documentation tests; reserve tests for code. Record each decision and move to the next question with fewer intervening steps.

### B06 — Point responsibilities and placement spacing

- Approved: Point adds, removes, and moves points; Line → Join connects existing points into an outline. Point Connect is superseded.
- New points cannot be placed over existing points. The subsequent spacing decision specifies at least one displayed point diameter between centres, checking only the selected drawing layer.
- The preceding batch's proposed Connect gesture, general post-finish behavior, and Enter-with-no-segment behavior were not approved by this answer.

### B06 — Placement distance and layer scope

- Approved: require at least one displayed point diameter between centres, measured in screen space against existing points on the selected drawing layer only. Reject too-close placement without automatic shifting or merging, independently of snapping.
- Zooming in permits physically closer placement; existing points do not move or become invalid merely because zoom changes their displayed separation. Other layers may still have coincident points without shared identities.
- Subsequent approval: Line Draw corners follow this limit; endpoint reuse is exempt, and existing point moves use geometric validity rather than screen-space spacing.

### B06 — Line Join input and repeated use

- Approved: two existing-point clicks with a following straight preview and validation; no self-connection or duplicate segment; keep Join selected for a new pair after success; Escape cancels the pending join.

### B06/B07 — Segment acquisition and point-based Line drawing

- Approved: point insertion acquires a nearby segment within a screen-pixel distance, independently of Grid/Drawing snapping. Line Draw stays selected after finish and starts a fresh operation on the next click.
- Line Draw shows a dashed segment to the cursor; placing the next point establishes a segment between Points. A LineSegment containing two Points and one Segment is proposed as the manipulation model.
- Still open: whether each placed segment commits immediately, how that affects Escape/Enter, and the concrete representation. The preceding proposal for Enter with only a start was not approved by this answer.

### B03/B06/B07 — Geometry references and per-placement commitment

- Approved: geometry objects store geometry; Points hold coordinates; LineSegments and layers reference geometry rather than duplicating it. Layer membership expresses ownership, including ownership of connections derived from its points.
- Approved: each accepted placed point/segment becomes permanent in memory. Escape discards only the trailing cursor preview and preserves placed geometry. This supersedes whole-line cancellation; Enter also ends drawing without rolling back or recommitting placed geometry.
- Exact registry/reference fields and history grouping remain open. Permanent does not mean already saved to disk or exempt from Delete/Undo.

### B14 — Placement groups and inverse actions

- Approved placement grouping; use action-specific records in ActionsBuffer to execute inverses for Undo and restore the corresponding action for Redo. Capacity defaults to 50 action groups, adjustable in Preferences from 1 to 1,000 whole groups. Reducing capacity trims oldest Undo entries, then furthest-future Redo entries as needed, without changing the drawing; increasing it does not restore discarded history.
- Combined Undo/Redo capacity, clearing Redo on new committed edits, and oldest-undoable-entry eviction on overflow are approved. Saving preserves history; reopening starts empty; the capacity preference persists separately. Returning to the saved document state clears the unsaved indicator. Canvas preview cancellation and field-local Undo/Redo are approved; remaining history scope is open.
