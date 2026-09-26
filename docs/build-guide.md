# Build screen: quick guide

The Build screen is where you draw your land. You draw three kinds of shapes,
each one inside the last:

- Field: the whole piece of land you are working with.
- Plot: a growing space inside a field.
- Area: a smaller part inside a plot.

A shape only counts once its outline is closed. When it closes, it gets a
light fill and shows as Active. An open outline is Inactive.

Nothing you draw is refused for breaking a drawing rule. Instead the shape
is marked Invalid: it turns red with dashed lines, gets a red ! in Layers,
and Properties says what is wrong. Rules include:

- a plot must sit inside its field, and an area inside its plot
- lines must not cross each other
- fields must not overlap other fields (the same for plots and areas)

An invalid shape is also Inactive, and so is everything inside it. Fix it
(for example, move the plot back into its field) and it becomes Active
again.


## Getting started

1. In Layers (right side), press + Field. A new field appears in the list.
2. In Drawing tools (left side), choose Line, then Draw.
3. Click on the grid to place the first corner, then click again for each
   next corner.
4. Click the first corner again to close the shape. It turns Active.
   (Or choose Circle and click twice for a round field.)
5. To add a plot, press Plot in Layers, then draw inside the field the
   same way.

A plot can only be added once there is an active field, and an area only
once there is an active plot.


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
Arc, Circle, Polygon, Pattern, Reference. A tool's functions show
underneath it.
Boolean is not a tool; it lives in the Operations panel.

Keyboard: V Select, P Point, L Line, A Arc, C Circle, G Polygon,
F Pattern, R Reference. To move anything, use Select.

The pointer tells you what a click will do. With Select it is the black
arrow from the Select button: clicks pick and move things. Every other
tool shows a crosshair: clicks add or remove geometry.

Select (black arrow, the starting tool)
- Click a point, a line, or the inside of a closed shape to select it.
  This works on any layer; the layer it belongs to is selected too.
- Drag to move it. Moving a whole shape also moves everything inside it.
- Where shapes are stacked, the innermost wins: an area before its plot,
  a plot before its field. Points win over lines, and lines over insides.
- Press and hold without moving to open a small menu listing everything
  under the pointer. Pick the one you mean.
- Shift-click adds to the selection within the same layer.
- Select has two functions, Marquee (the default) and Lasso. Drag from
  empty ground to select several things at once:
  - Marquee draws a dashed rectangle; Lasso (the pointer turns into a
    lasso) draws any outline you like and closes it back to where you
    started.
  - Anything the outline touches is selected, even if only part of it
    is inside. Things about to be picked light up while you drag.
  - A selection stays on one layer. The selected layer is used if the
    outline touches it; otherwise the innermost land wins (an area before
    its plot), as with a click. Locked layers are skipped.
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
  or zoom in to place points closer together.
- Delete: click a point to remove it along with its lines.

Line
- Draw: click to add corners one after another. Click an open end point to
  carry on an earlier line. Press Enter or Esc to stop.
- Join: click two existing points to connect them with a line. The point
  you just joined becomes the start of the next join, so keep clicking
  points to join them in a run. Esc, Enter or another tool ends the run;
  closing a loop ends it too.
- Delete: click a straight or curved edge to remove it. Its points stay.

Arc
- Click the start, a point on the curve, then the end. The first two
  clicks are temporary; Esc cancels them. You can reuse open endpoints to
  join an arc to straight edges. Three points in a straight line cannot
  make an arc.

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
  shape. Combine them with Operations > Boolean.

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
  shape. A plot covering a field's hole is Invalid, even when its corners
  are all inside the outer outline. The same rule applies to areas in plots.

Pattern
- Choose None or one of six patterns (Diagonal, Rows, Crosshatch, Grid,
  Dots, Crosses), then click inside the selected layer's closed boundary.
  Clicks in a hole or outside do nothing. The tool stays chosen.
- Patterns are for looks only: area and land checks are unchanged. They
  show on Active land; Invalid or Inactive land shows its grey hatch
  instead, and an open outline shows no pattern. A parent's pattern is
  cut away under the plots or areas inside it.
- The Pattern menu in Properties (LOOK) changes the same setting. Each
  change is one Undo step and is saved with the drawing.

Reference (pictures to trace over)
- Choose Reference (or press R). Properties always shows the same
  layout: Upload image, the selected picture's name with a bin, then
  Opacity and Distance. With no picture selected they are greyed out.
- Upload image: pick a PNG, JPEG or WebP site plan or photo (up to 20 MB).
  It is placed in the middle of the view, sized to fit, under all the
  land, and named after its file. Upload again to add more pictures.
- Click the name to rename it; Enter or clicking away saves, Esc cancels,
  and a blank name goes back to the file name. The bin removes the
  picture.
- Every picture goes in one Reference layer at the bottom of Layers. Each
  picture is its own row under it, like the shapes under a field; "no
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
line that crosses another, or a plot outside its field). The click still
works; the status bar at the bottom says what became invalid, and Undo
takes it back.

A few things are still refused because they cannot make sense, such as a
point joining a third line. The status bar says why.


## Moving around

- Zoom: mouse wheel, or the − and + buttons in the bottom-right corner.
  Click the zoom percentage to fit the whole drawing.
- Pan: drag with the middle mouse button, or hold Space and drag.
- View > Fit drawing: shows the whole drawing.
- View > Reset view: back to 100%.

The bar next to the zoom shows how long one grid square is, in your
chosen units.


## Layers and Properties

- Click a layer in Layers to work on it. Its details show in Properties.
- In Properties you can rename the layer (pencil button) and set its
  options, such as colour or soil drainage. Fields also record a soil
  sample (pH, phosphorus, potassium, calcium, magnesium, CEC,
  conductivity, organic matter): type a number, or leave it blank. Values
  are kept exactly as typed; units and lab method are not recorded, so
  the app does not convert or judge them. Net area excludes holes and
  includes curved edges; it is displayed in m² or ft² with your chosen units.
- The bin icon (shown when you point at a layer) deletes it, and
  everything inside it. You are asked first.
- The padlock next to the bin locks a layer once it is finished. A
  locked layer, and everything inside it, cannot be drawn on, moved,
  renamed, changed, or deleted, and Select clicks pass through it to the
  land underneath. You can still select it in Layers to read its
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
normally, with those shapes marked Invalid. New files preserve arc edges,
holes and unfinished Boolean operands using schema 2. Older schema 1
drawings still open, but older app versions cannot read schema 2 files.


## Controls and preferences

- Controls panel: Units (Dimensions in ft or m; Area in ft², m² or
  acres), Snapping (to the grid) on or off, and Guides on or off.

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
  - Canvas: zoom limits, how many undo steps to keep, and menu size.
  - Style: line width, and grid thickness, colour and opacity.
  - Notifications: whether messages pop up at the top or bottom.
  Typed values are kept while you switch categories; press Apply to use
  them. The toast position takes effect straight away.

Short messages (saved, exported, errors such as "Add a Field layer to
start drawing.") pop up as toasts and go away on their own. Point at them
to spread them out and keep them on screen; the × dismisses one.

Lengths are always stored in metres. Changing units only changes how
numbers are shown.


## Window size

The Build screen needs a window of at least 800 × 600 to edit. In a smaller
window the drawing is shown but cannot be edited. Saving still works.
