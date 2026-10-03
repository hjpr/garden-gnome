# Garden tools guide

Garden Gnome opens on Home, which shows five tools: Plan, Seed Vault,
Greenhouse, Grow and Harvest. Each card shows a live count. To move
between tools, use the leaf menu at the top left of any tool. It also
has Home.

## Seed Vault
- Add variety: pick a named variety from the bundled Johnny's catalog.
  Each row shows the variety first and its crop in smaller grey text on the
  right. Search matches variety names, crop names and categories (such as
  Herbs). Select a result, then press Add or Enter; no name entry is needed.
  Existing saved varieties are unchanged. Growing values still start from
  the crop's defaults, not variety-specific measurements.
- A blank box uses the crop's value, shown greyed (for example
  "70–80 days"). Type a value to override it for this variety. Enter or
  clicking away keeps it; Esc puts it back.
- The right side shows the crop's growing notes from Johnny's Selected
  Seeds. Values marked * are estimates.
- The bin on each variety row, left of its season icon, removes that
  variety from the vault.
- To filter the list, type in Search varieties or use the chips
  (Vegetables, Herbs, Cool, Warm, Transplant, Direct sow).
- Greenhouse, Grow and Harvest show only the farm open in Plan (its
  name is on Home). Its climate and sowings are saved with that farm:
  sowing, planting out, finishing and climate changes are Undo steps in
  Plan and need a Save, like a drawing change. A new blank farm has
  empty calendars. The last farm saved or opened reopens at start-up.
- Sowings and climate from before farms held them move into the farm
  open the first time this version runs; save that farm to keep them.
- The Seed Vault belongs to this browser, not to a farm. The arrows
  beside Add variety import and export it as a .seedvault file, to keep
  a copy or move it to another browser. Importing adds new varieties and
  skips ones already in the vault (same crop and name).

## Plan: Build and Plant
- Ground tool functions (beds only): Fallow is unprepared ground that
  nothing is planted on; Flat and Row prepare a bed's soil. New beds
  start Flat.
- For Row ground, Properties > GROUND > Border reserves a clear walkway
  inside the bed's outline. Row width, Spacing and Border use inches
  when drawing units are feet, and metres when drawing units are metres.
  Enter 60 inches for a five-foot perimeter path. Rows shorten or split to follow
  uneven edges, curves and holes, keeping their full width clear of the
  border. Bordered rows are centred, sharing leftover space equally at
  opposite edges rather than adding it all to one side. The border is a
  minimum clearance; row widths and spacing are kept as entered.
  Row and plant counts update without changing the bed shape.
  Zero keeps the existing edge-to-edge layout; if no rows fit, the count
  is zero. Border changes are saved with the drawing and support Undo.
- A planting (Layers > Add layer > Planting layer) is drawn over Flat or
  Row beds on the same property to say what is planted there. It
  follows the soil under it: over Row ground, plants go only along the
  rows (a wide row gets several lines separated by Size plus Spacing);
  over Flat ground, they go on a grid running that bed's Direction;
  over a fallow bed, nothing is planted.
- If beds overlap, the topmost Flat or Row bed in Layers wins. Its
  paths and borders stay unplanted; holes reveal the soil below.
  Overlapping beds do not duplicate plants or inflate the count.
- The Build | Plant switch in the header changes mode. Plant locks
  all geometry. Select picks existing plantings without moving or
  reshaping them. Add, remove, or reshape layers in Build instead.
- Plant shows Drawing tools (Select only) and Seeds on the left, with
  Properties and Layers on the right. Operations and Controls return
  when you switch back to Build.
- Undo and Redo still work for planting changes, but layout changes
  require switching back to Build.
- In Plant mode the Seeds panel lists your Seed Vault. Drag a seed onto
  a planting to plant it (the planting lights up green where it would
  land), or click a seed to plant the selected planting.
- Only plantings show Properties > GROW; they do not show ground
  options. Size is the plant diameter, and Spacing is the empty gap
  between plants. Plant centres are Size + Spacing apart, along rows
  and between planting lines. Zero spacing lets neighbouring plants
  touch. Changing spacing updates the layout and Plants count, including
  on a single row, without changing the plant diameter.
- Size starts at the variety's minimum in-row recommendation; Spacing
  starts at its minimum between-row recommendation minus Size, or zero
  if that difference is negative. Type to change either for this
  planting. Plants over Row ground follow the rows; over Flat ground
  they follow that bed's Direction (set in its Properties > GROUND).
  Plants (under Seed) shows how many fit. Sown and Transplanted are
  dates: click one to pick a day from the calendar. Sown alone means
  sown in place; adding Transplanted means it was started elsewhere and
  set out that day (the × clears it). Transplanted needs a Sown date and
  cannot be earlier. Either date makes the planting show in Harvest,
  named after the planting layer, counting from Transplanted when set,
  otherwise from Sown. Changing the seed changes that sowing; removing
  the seed or deleting the layer removes it. The bin removes the seed.

## Grow
- Set Hardiness to your USDA zone. Last frost and First frost show the
  zone's typical dates in grey; type your own to replace them (for
  example "Apr 20").
- Grow is for sowing in place; seed started in trays is in Greenhouse.
  Plan first: you can only sow plantings already on the map (Plan >
  Plant mode, a planting with a seed and nothing sown yet).
- The calendar has two sections. Growing, on top, is what is sown
  (germination in grey, harvest in red). Upcoming, below and faded, is
  what is not in the ground yet: plantings waiting to be sown and Seed
  Vault varieties in no planting yet ("not planned"), each with its
  sowing window. The solid part of a window is the best time.
- Both sections run soonest first: Growing by when picking starts,
  Upcoming by when the best sowing time starts. Higher in the list means
  sooner, even when the dates are scrolled off screen.
- Start next: Add plant, then the direct-sow windows open now or opening within a year.
  Planned ones have a sprout button that opens the Sow dialog for that
  planting; unplanned ones are greyed ("Add it to a planting in Plan
  first"). Add plant offers every planting waiting to be sown.
- The Sow dialog shows the planting, the Sown date (today unless you
  change it) and how many plants it holds. That number comes from the
  planting's Size, Spacing and Lines in Plan.

## Planting lines
- A planting over Row ground has Lines in its GROW properties: how many
  lines of plants go along each row. All (the default) fills the row
  with as many as fit; type a number, or use the arrows, to plant fewer.
- The most you can enter is what fits across the row at the planting's
  Size and Spacing ("At most 5 lines fit. Reduce Spacing for more").
  For more lines, reduce Spacing or Size. Widening Spacing later lowers
  Lines to the new most. Over Flat ground plants form a grid and Lines
  is greyed.

## Greenhouse
- The calendar has two sections. Growing, on top, is each flat or pot
  in the greenhouse, with its germination bar (grey) and the dates it
  can be planted out (blue); chips show Growing, Ready or Overdue.
  Upcoming, below and faded, is seed to start within a year, with
  its start window (amber).
- Both sections run soonest first: Growing by when it is ready to plant
  out, Upcoming by when the best start time begins.
- The arrow button (Planted out today) moves the tray into the ground.
- Start next: trays to start within a year.

## Harvest
- Shows when each planting comes ready and how long it keeps picking.
  Solid bars are crops in the ground; faded bars are trays whose dates
  are still estimates.
- The double tick (Harvest finished) removes a planting from the
  calendar.

Everything in these tools is saved in this browser as you go.

## Updating the crop catalog
Run `python3 tools/johnnys-catalog/scrape.py` for growing defaults and
`python3 tools/johnnys-catalog/scrape_varieties.py --refresh` for named varieties,
then rebuild the app. The variety list is a bundled catalog snapshot, not live
stock availability. Some crops and cultivation-specific categories have no
separately listed varieties. See
`tools/johnnys-catalog/README.md`.

## Greenhouse flats and pots
- Greenhouse's Start next lists seed to start within a year. Its
  start button opens the dialog with that seed already chosen. Add plant
  (top of Start next) starts anything else; pick the seed in the dialog.
  Greenhouse starts do not need a planting first: drag them onto one in
  Plant mode when you know where they go.
- The dialog asks for the Start date (today unless you change it, so
  you can enter what you will start in a few days), then Flats or Pots.
  Flats: how many flats and cells per flat; each cell is one plant.
  Pots: how many pots; one plant each. It shows how many plants you
  will have to plant out.
- In Plan's Plant mode, the Greenhouse panel under Seeds lists every
  flat and pot still in the greenhouse, ready or not, with a Growing,
  Ready or Overdue tag, the plants each gives, and when it is ready.
- Drag one onto a planting to plan where it goes: the planting takes
  that seed, and its Transplanted date is set to the day the plants
  are ready (today if that has passed). It stays in the greenhouse
  until that day. Removing the seed or the planting sends it back to
  the greenhouse unplanned.

## Calendars
- Grow, Greenhouse and Harvest show today's date above the months.
  Over the calendar, scroll the mouse wheel to zoom in (fewer days,
  day numbers appear) or out (up to about three years); drag to move
  earlier or later. Today brings the view back. Darker lines mark the
  start of each week (Monday), fainter ones each day; zoomed far out,
  the darker lines mark months.
