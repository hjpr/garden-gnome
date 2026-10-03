# Plan screen: quick guide

The Plan screen is where you plan your farm. Planning has two parts,
switched in the header: Build, where you draw your land, and Plant,
where you place seed in plantings. Layers lists each kind of layer on
its own, so what a layer is for is always visible:

- Property: land you hold. Properties may not overlap one another.
- Bed: ground inside a property: Fallow, Flat, or Row.
- Planting: what grows where. Draw it over beds and plant it from the
  Seed Vault; plants follow the bed underneath.
- Reference: pictures to trace over (see Reference below).

Beds and plantings (together called zones below) must stay inside the
property they belong to, but within it they may overlap and touch each
other freely. In Layers each property lists its BEDS, then its
PLANTINGS.

A shape only counts once its outline is closed. When it closes, it gets a
light fill and shows as Active. An open outline is Inactive.

Nothing you draw is refused for breaking a drawing rule. Instead the shape
is marked Invalid: it turns red with dashed lines, gets a red ! in Layers,
and Properties says what is wrong.

Every layer must be finished: each outline closed, no outline crossing
itself, and no loose lines or points left over. Beyond that:

- a zone must sit inside its own property (touching the property line is
  fine); its shapes may overlap and cross each other and other zones
- a property must not overlap another property
- the shapes of one property must not overlap or cross each other

An invalid layer is also Inactive, and so are the zones of an inactive
property. Fix it (for example, move the zone back inside its property)
and it becomes Active again.


## Getting started

1. In Layers (right side), press + Add layer and choose Property layer.
   A new property appears in the list.
2. In Drawing tools (left side), choose Line, then Straight.
3. Click on the grid to place the first corner, then click again for each
   next corner.
4. Click the first corner again to close the shape. It turns Active.
   (Or choose Circle and click twice for a round property.)
5. Choose Add layer > Bed layer and draw your beds the same way. A new
   bed is Flat; switch it to Fallow or Row with the Ground tool.
6. Choose Add layer > Planting layer and draw where a crop goes, over
   the beds. Plant it in Plant mode (see the garden tools guide).
   Add layer > Reference layer uploads a picture to trace over.

Until there is a property, every choice but Property layer is greyed
out.

A bed or planting goes under the selected property, or under the
property of the selected bed or planting. It can only be added once that
property is Active.


## The screen

- Left side: Drawing tools, Operations and Controls. Right side: Properties
  and Layers.
- Each side has a slim strip along the window edge. Click the strip (or
  its arrow) to fold that side away and give the drawing more room;
  click again to bring it back. The icons on the strip show which panels
  are open; click one to open or collapse that panel.
- Click a panel's heading to collapse it to just the heading.
- Drag a panel by the dotted grip at the left of its heading to move it
  up or down within its side.
- Drag the inner edge of either side (the pointer becomes a resize
  arrow) to make it wider or narrower. The width is kept when the side is
  folded and reopened, and remembered with the drawing.
- View menu: fold either side, or hide and show individual panels.
- Your layout is remembered for each drawing.


## Tools

Tools are laid out three to a row, in this order: Select, Point, Line,
Arc, Circle, Polygon, Ground, Feature, Reference. A tool's functions show
underneath it.
Boolean is not a tool; it lives in the Operations panel.

Keyboard: V Select, P Point, L Line, A Arc, C Circle, G Polygon,
D Ground, F Feature, R Reference. To move anything, use Select.

The pointer tells you what a click will do. With Select it is the black
arrow from the Select button: clicks pick and move things. Every other
tool shows a crosshair: clicks add or remove geometry.

Select (black arrow, the starting tool)
- Click a point, a line, or the inside of a closed shape to select it.
  This works on any layer; the layer it belongs to is selected too.
- Drag to move it. Moving a whole property shape also moves its zones'
  shapes that lie inside it. Moving a zone never moves another zone,
  even one it overlaps.
- Where shapes are stacked, a zone wins over its property, and where
  zones overlap, the one drawn later (lower in Layers) wins. Points win
  over lines, and lines over insides.
- Press and hold without moving to open a small menu listing everything
  under the pointer. Pick the one you mean.
- Shift-click adds to the selection within the same layer.
- Click empty ground to deselect everything, including the layer.
- Select has two functions, Marquee (the default) and Lasso. Drag from
  empty ground to select several things at once:
  - Marquee draws a dashed rectangle; Lasso (the pointer turns into a
    lasso) draws any outline you like and closes it back to where you
    started.
  - Anything the outline touches is selected, even if only part of it
    is inside. Things about to be picked light up while you drag.
  - A selection stays on one layer. The selected layer is used if the
    outline touches it; otherwise a zone wins over a property, as with a
    click. Locked layers are skipped.
  - Hold Shift as you start to add to the selection. An outline that
    touches nothing clears the selection.
- On a circle: drag its edge to resize it, or its inside (or centre
  point) to move it.
- A selected shape or circle gets a dashed box with a dot at each corner
  and edge middle. The status bar shows the box's width (W) and height
  (H), live while you drag.
  - Corner dot: drag to scale from the opposite corner. Hold Shift to
    keep the proportions.
  - Edge (the dashed line or its middle dot): drag to stretch one way.
  - Just outside a corner the pointer turns into a curved arrow: drag to
    rotate around the box's centre. The status bar shows the angle. Hold
    Shift for 15° steps. Rotating carries the land inside, as moving
    does; scaling does not.
  - Circles always scale evenly. Scale, Rotate and Move are each one
    Undo step.

Point (a dot)
- Place: click to place a loose point. Click on a straight or curved edge
  to split it with a new point. Splitting an arc preserves its curve.
- New points must be at least one point marker apart on screen. A click
  too close to another point is refused; click the point itself to use it,
  or zoom in to place points closer together. On a zone, a new point may
  land right on the corner of a finished shape, as zone shapes may touch.
- Delete: click a point to remove it along with its lines.

Line
- Straight: click to add corners one after another. Click an existing
  point to draw to it: a loose point carries the line on, and an open end
  or the first corner ends it. Start on a point to join points in a run.
  Press Enter or Esc to stop.
- Curve: works like Straight, pen style. Click for a sharp corner, or
  press and drag to pull out two handles that bend the line smoothly
  through that point. The next piece leaves along the handle you pulled.
- To reshape a curve, select it (or one of its points) with Select and
  drag a handle dot. At a smooth point the opposite handle swings round
  with it. Area and land checks follow the curve to within half a
  millimetre.
- To remove a line, pick it with Select and press Delete. Its points stay.

Arc
- 3-point: click the start, a point on the curve, then the end.
- Start-end: click the start, then the end, then move out and click to
  set the middle of the arc. The arc stays symmetric; how far you move
  from the straight line between the ends sets how far it bends.
- The first two clicks are temporary; Esc cancels them. You can reuse
  open endpoints to join an arc to straight edges. Three points in a
  straight line cannot make an arc.

Circle
- Center: click the centre, then click to set the size. Clicking a ringed
  point uses it as the centre.
- 2-point: click one side, then the opposite side. The two clicks set the
  width.
- The diameter shows while you size it. Esc forgets the first click.
- To remove a circle, delete it with the bin in Layers, or delete its
  centre point with Point > Delete.

Polygon
- Regular: click the centre, then click where the first corner goes. That
  click sets both the size and the turn. Set the number of sides (3 to 24,
  6 to start) with Sides under the functions.
- Rectangle: click one corner, then the opposite corner.
- The shape is added as ordinary points and straight lines in one step, so
  Undo removes it whole and Point, Line and Select can edit it afterwards.
  Esc forgets the first click.
- A polygon drawn on a layer that already has a shape is added as another
  shape. On a property, shapes that overlap must be combined with
  Operations > Boolean; on a zone they may stay as they are.

Operations > Boolean (a panel on the left, under Drawing tools)
- Select the shapes first: with Select, click one shape and Shift-click
  the others. Shift-click in Layers works too. All must be closed shapes
  or circles on the same layer.
- Then press Union or Subtract. The buttons stay greyed out until two or
  more shapes are selected. Point at a button to preview the result on the
  canvas: green if it will work, red with the reason in the status bar if
  not.
- Union merges the selected shapes into one. Each must overlap, or share
  an edge with, another selected shape; touching at a single point is not
  enough.
- Subtract uses the selected shape highest in the Layers stack as the
  cutter. It cuts every other selected shape and is then removed. Change
  which shape is on top with the up and down arrows in Layers.
- Subtracting a circle entirely inside a shape makes a hole. Cutting
  across the edge makes a curved notch. A cut that splits a shape leaves
  separate shapes. A cut that would remove a shape entirely is refused.
- The result is selected afterwards. One Undo restores the original
  shapes.
- Use Select to move result edges or points. Moving an arc endpoint keeps
  its sweep angle; moving the whole shape carries its holes along too.
- Holes are not land: clicking inside a hole does not select the surrounding
  shape. A zone covering its property's hole is Invalid, even when its
  corners are all inside the outer outline. A property that spills out
  of another property's hole overlaps it and is Invalid.

Operations > Align (under Boolean)
- Select exactly two items on one layer with Select: click the one to
  align to, then Shift-click the one to move. Order matters; the first
  stays put.
- Left, Right, Top and Bottom line up that edge of the second item's
  bounds with the same edge of the first. Center puts the second item's
  centre on the first's centre, in both directions.
- Point at a button to preview the move. Aligning is kept even when it
  makes a property's shapes overlap; the property is then marked
  Invalid. One Undo puts the item back.
- Moving a whole property shape carries its zones' shapes inside it
  along, as a drag does. Items that share points cannot be aligned.

Ground (beds only)
- Fallow, Flat or Row, then click inside the selected bed. The whole bed
  gets that ground; the tool stays chosen. Each change is one Undo step.
  Plantings are added in Layers, not with this tool.
- Row ground uses Row width, Spacing (the path between rows) and
  Direction (degrees clockwise from up the screen: 0 runs rows up and
  down, 90 left to right). These controls appear only for Row ground,
  and keep their values when you switch away.
- Rows are laid edge to edge from one side of each of the bed's shapes.
  Properties shows how many rows fit and their total length.

Feature
- Raised bed, Greenhouse or High tunnel, then click to place one at its
  usual size (8 × 4 ft bed, 12 × 8 ft greenhouse, 30 × 14 ft tunnel),
  centred on the pointer. Features sit on top of the land and need no
  layer.
- Select picks a feature before the inside of a shape (points and lines
  still win) and drags it. Its Properties show the name (click to
  rename, bin to delete), Length, Width, Height, Rotation and footprint.
  Delete removes the selected feature.
- In Render a high tunnel is built from 5 ft sections (an end at each
  end, middle sections between), so any length looks right. Its drawn
  length is rounded to the nearest 5 ft: a 79 ft tunnel shows as 80 ft.
  The number in Properties is kept exactly as typed.

Reference (pictures to trace over)
- Choose Reference (or press R). If the drawing has no Reference layer
  yet, an empty one is added at the bottom of Layers and selected (one
  Undo step). Properties always shows the same layout: Upload image,
  the selected picture's name with a bin, then Opacity and Distance.
  With no picture selected they are greyed out.
- Upload image: with the Reference layer or one of its pictures
  selected, pick a PNG, JPEG or WebP site plan or photo (up to 20 MB).
  With anything else selected, the status bar asks you to select a
  reference layer first.
  It is placed in the middle of the view, sized to fit, under all the
  land, and named after its file. Upload again to add more pictures.
- Click the name to rename it; Enter or clicking away saves, Esc cancels,
  and a blank name goes back to the file name. The bin removes the
  picture.
- Every picture goes in one Reference layer at the bottom of Layers. Each
  picture is its own row under it, like the shapes under a property; "no
  scale" marks ones not yet calibrated. Later pictures sit on top.
- Picture rows: click to select it and open its Properties; hover for up
  and down (which picture lies on top), lock and delete. The Reference
  row's lock and delete act on every picture at once.
- Move a picture with Select: drag its inside. Land drawn over it is
  picked first, so click an empty part of the picture. Once selected,
  drag a corner handle to scale it; it keeps its shape.
- Set each picture's true scale separately: with Reference > Ref. line,
  click the two ends of a distance you know on that picture. The line
  goes on the picture you click (the selected one if it is under the
  pointer, so a picture lying underneath can be measured too). Then type
  its real length in Properties > Scale > Distance (the box turns on
  once the line is drawn) and press Enter or click away. Only that picture resizes, and Scale shows Calibrated.
- Moving a picture keeps its calibration. Scaling it by hand, or drawing
  a new line on it, clears its distance until you enter one again.
- Opacity (Properties > Look) fades each picture so the drawing shows on
  top. The lock on a picture's row in Layers stops it being picked, moved
  or measured by accident.
- Delete while a picture is selected also removes it. Each change is
  one Undo step.
- Very large pictures are drawn from a copy no more than 4096 pixels on
  the long side, because browsers cannot draw bigger ones. The saved file
  keeps the full picture.
- Pictures are saved inside the drawing and in exported .ggnome files.
  Drawings saved with one reference picture by the previous version open
  with it as Image 1.

While you draw or drag, the dashed preview is green when the result will
be valid and red when it will leave something invalid (for example, a
line that crosses another in a property, or a zone line leaving its
property). On a zone a new outline may cross finished shapes. The click
still works; the status bar at the bottom says what became invalid, and
Undo takes it back.

A few things are still refused because they cannot make sense, such as a
point joining a third line. The status bar says why.


## Moving around

- The view is a camera looking straight down. The bottom-right corner
  shows its height above the ground: 5 ft to 500 ft unless you change
  the range in Edit > Preferences > Canvas.
- Zoom: mouse wheel, or the − and + buttons in the bottom-right corner,
  which lower and raise the camera. Click the camera height to fit the
  whole drawing.
- Pan: drag with the middle mouse button, or hold Space and drag.
- View > Fit drawing: shows the whole drawing.
- View > Reset view: back to 100 ft over the origin (or the nearest
  height your range allows).

The bar next to the camera height shows how long one grid square is, in
your chosen units. The grid always uses round sizes: 0.5, 1, 5, 10 or
20 ft (0.1, 0.5, 1, 2, 5, 10, 20 or 50 m), getting coarser as you zoom out.


## Layers and Properties

- Click a layer in Layers to work on it. Its details show in Properties.
- In Properties you can rename the layer (pencil button). Properties have
  a colour option.
- A bed's bar above its name shows its ground: grey for Fallow bed, burnt
  orange for Flat bed, mint green for Row bed. A fallow bed shows only
  colour; Flat adds Direction, the heading of the plant grid that
  plantings lay on it; Row adds row controls. A planting shows only the
  GROW options.
- Net area excludes holes and includes curved edges; it is displayed in
  m² or ft² with your chosen units. Where a zone's shapes overlap, the
  shared ground counts once.
- The eye (shown when you point at a layer) hides it: it is not drawn,
  clicks pass through it, and it cannot be drawn on until shown again.
  Hiding a property hides its beds and plantings; the Reference row has
  its own eye. Hidden layers stay hidden for this drawing on this
  device, and hiding is not an Undo step.
- The bin icon (shown when you point at a layer) deletes it. Deleting a
  property deletes its beds and plantings too. You are asked first.
- The padlock next to the bin locks a layer once it is finished. A
  locked layer, and every zone under a locked property, cannot be drawn
  on, moved, renamed, changed, or deleted, and Select clicks pass through
  it to the land underneath. You can still select it in Layers to read its
  details. Click the padlock again (or Unlock in Properties) to unlock.
  Locking is saved with the drawing and can be undone.


## Undo and redo

Use the arrows at the top right, the Edit menu, or:

- Undo: Ctrl+Z
- Redo: Ctrl+Shift+Z or Ctrl+Y

Undo is unavailable while you have unapplied text in the Properties panel.
Apply or clear the text first.


## Saving and opening

Drawings are saved in your browser.

- File > Save (Ctrl+S): saves the drawing. The first time, you give it a
  name.
- File > Save as (Ctrl+Shift+S): saves a copy under a new name.
- File > Open (Ctrl+O): pick a saved drawing from the list.
- File > New (Ctrl+N): starts a blank drawing.
- File > Close drawing: closes it and leaves a blank drawing in its place.

New, Open and Close offer to save unsaved work first. The first save asks
the browser to keep your drawings even when disk space runs low; the
browser may decline. Your view (zoom and position) is remembered when you
switch away from or close the tab. Switching away mid-drawing cancels the
unfinished shape, as Esc does.

To rename the drawing, click the pencil beside its name at the top (or
double-click the name), type, and press Enter or click away. Esc keeps the
old name. The new name is stored with the next Save.

A dot after the drawing name at the top means there are unsaved changes.
The browser will also warn you before you close the tab.

To keep a copy outside the browser, or move a drawing to another computer:

- File > Export .ggnome file downloads the drawing as a file.
- File > Open, then Import .ggnome file, loads one back in.

Files that are damaged are refused, with a message explaining why, and
your current drawing is left as it was. A file with invalid shapes opens
normally, with those shapes marked Invalid. A file made by a newer
version of Garden Gnome is refused rather than opened with parts missing.


## Controls and preferences

- Controls panel: View (Wireframe or Render), Units (Dimensions in ft
  or m; Area in ft², m² or acres), Snapping (to the grid) on or off, and
  Guides on or off.
- Render shows the farm from above: open land is wild grass, a property
  is lawn, a zone is tidy dirt, Flat ground is prepared soil and Row
  ground shows its rows. Features show as pictures. Only the selected
  layer's outline is drawn, and reference pictures are hidden. Every
  tool works the same in both views; the choice is remembered with the
  workspace, not the drawing.

Guides line things up with their neighbours while you draw or move them.
Rest the pointer on a point, line or circle for a moment; small blue
crosses show what it offers. Then draw, or grab something else with
Select and move it. When it comes close, it is pulled into line and a
dashed guide shows the alignment.

- A point: its horizontal and vertical.
- A line: its middle, which you snap onto directly; the line's own path,
  carried on past both ends; and the perpendicular through its middle.
  An arc's path is its whole circle.
- A circle: its leftmost, rightmost, top and bottom points, which you
  snap onto directly (no guide lines).

For a horizontal or vertical line through a line's middle, place a point
there first and use that point as the guide.

When moving a whole shape or circle, whichever of its corners (or a
circle's outermost points) is closest lines up. With Snapping also on, a
guide wins on its axis and the grid places the other.
- Edit > Preferences, in three categories down the left:
  - Canvas: the lowest and highest camera height, in your chosen units
    (lower for a small plot, higher for a large property), how many
    undo steps to keep, and menu size.
  - Style: line width, and grid thickness, colour and opacity.
  - Notifications: whether messages pop up at the top or bottom.
  Typed values are kept while you switch categories; press Apply to use
  them. The toast position takes effect straight away.

Short messages (saved, exported, errors such as "Add a Property layer to
start drawing.") pop up as toasts and go away on their own. Point at them
to spread them out and keep them on screen; the × dismisses one.

Lengths are always stored in metres. Changing units only changes how
numbers are shown.


## Window size

The Plan screen needs a window of at least 800 × 600 to edit. In a smaller
window the drawing is shown but cannot be edited. Saving still works.
