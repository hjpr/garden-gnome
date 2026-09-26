# Milestone 2: curved land and Boolean tools

This expands milestone 2. The old design's ban on holes, arcs, and a second
closed shape on a layer no longer applies. A layer still has one connected
piece of occupied land. The hierarchy stays Field → Plot → Area.

## Geometry increment

- Keep both Circle functions: Center and 2-point.
- Tools, in order: Select, Point, Line, Arc, Circle, Polygon, Boolean.
- Add Arc as its own tool: three clicks, start, a point the arc passes
  through, end. The first two clicks are temporary; Escape cancels without
  creating points.
- Add Polygon → Regular (centre, then a corner; 3 to 24 sides, 6 by default)
  and Polygon → Rectangle (two opposite corners). Both add ordinary points
  and straight lines in one Undo step.
- Select shows its own arrow as the canvas pointer; tools that add or
  remove geometry show a crosshair. The Point tool icon is a dot.
- Add Boolean → Union and Subtract. Draw an additional closed shape or circle
  on the same layer, then click that operand with the Boolean function.
  Union adds it to the layer boundary; Subtract cuts it out of the boundary.
- Additional closed shapes are construction operands, not extra occupied
  land. Drawing one does not replace the designated boundary or change its
  net area. Operands may cross the boundary so edge notches and extensions
  are possible.
- A successful Boolean consumes the boundary and chosen operand, producing
  a new editable boundary. Unrelated construction stays. The whole operation
  is one Undo step; Redo restores the same result.
- Allow one outer outline and any number of holes. Refuse empty results,
  disconnected pieces, or unrepresentable/pinched results without changing
  the drawing. A failed operation must not consume either operand.
- The result has real editable points and straight or circular-arc edges,
  not a bitmap, flattened polygon approximation, or live A-minus-B recipe.
  Moving an arc endpoint preserves its signed sweep and updates its circle.
  Inserting a point splits the actual arc, not its chord.
- Properties shows net area in square metres or square feet. Holes subtract
  from that area. Circle and arc contributions use analytical geometry;
  camera zoom and display units do not change the stored shape.

## Legality and persistence

All tools, previews, history, and loaded drawings use the same region rules.
Test occupied land, not just a few vertices or bounding boxes:

- A plot must stay inside its field, and an area inside its plot.
- Covering a parent's hole is illegal even if every child corner and every
  child boundary edge is inside the parent's outer outline.
- A hole shared by parent and child is legal; a child wholly inside a
  parent's cut-out is not.
- Entire curved edges must fit. An arc can leave the parent even when its
  endpoints fit. The same is true of straight edges crossing concave notches.
- Siblings may touch but cannot share occupied land. A sibling inside
  another sibling's hole is not an overlap.
- A parent Boolean may make existing children invalid/inactive; retain them
  and report why. Undo restores both the shape and derived validity.
- Rule-breaking editable geometry remains in the drawing, marked Invalid.
  Refuse only structurally impossible edits or Boolean inputs/results whose
  topology cannot be represented safely.
- Save arc curvature, outer and hole rings, staged operands, and ID counters.
  File schema 2 prevents older readers from silently replacing arcs with
  chords or filling holes. Schema 1 drawings still open.

## Rest of milestone 2 (done)

- Pattern tool (the decorative Fill), last in the tool list: None plus six
  patterns (Diagonal, Rows, Crosshatch, Grid, Dots, Crosses), extending the
  three first planned. Plot patterns live in PlotProperties.pattern; Field
  and Area patterns on their boundary shape or circle. Invalid/inactive
  hatch overrides, open outlines show none, and parent patterns are masked
  under closed children. Saved names are unchanged, so schema 2 still holds.
- Extended recorded properties: the eight soil sample values are editable
  in Field Properties. They are observations with unspecified units and
  methods, not agronomic recommendations or canvas lengths.
- Remaining milestone 1/2 items closed: Ctrl+N, File > Close drawing,
  typed circle diameter, minimum on-screen spacing between new points,
  persistent-storage request, saving the view when the tab is hidden, and
  cancelling unfinished shapes when the app loses focus.
- Browser-only by design: drawings are stored in the browser (IndexedDB)
  and exported as .ggnome files. A native desktop save path is not built.

Reference images remain milestone 3. Planting rows and mounds remain
milestone 4. Disconnected occupied pieces in one layer are still out of scope.
