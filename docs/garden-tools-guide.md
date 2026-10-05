# Garden tools guide

Garden Gnome opens on Home, which shows three tools in the order you
use them: Seed Vault, Plan and Grow. Each card shows a live count. To
move between tools, use the leaf menu at the top left of any tool. It
also has Home.

The flow: enter your seed in the Seed Vault. In Plan, mark out the farm
(Build), then drag your seed onto it (Plant). Seed you start in trays is
started in Grow > Transplant, and from then on it is in Plant mode's
Greenhouse panel to drag onto a planting too. Grow follows everything
from sowing to harvest.

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
- Reorder from Johnny's, between SEED and GROWING, opens the variety's
  Johnny's product page in a new tab. It is greyed for a variety the
  Johnny's catalog does not list (hover shows why).
- Cover crops (clovers, rye, buckwheat, mixes and more) can be added
  like any variety. Their notes show Johnny's comparison chart (sowing
  season, germination temperature, hardiness, seeding rates, depth,
  benefits) and growing notes. They have no GROWING overrides, get no
  sowing recommendations, and are sown on Cover beds (see below).
- To filter the list, type in Search varieties or use the chips
  (Vegetables, Herbs, Cover crops, Cool, Warm, Transplant, Direct sow).
- Grow shows only the farm open in Plan (its
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
- Ground tool functions (beds only), in order: Fallow is unprepared
  ground that nothing is planted on; Cover is a bed sown with a cover
  crop; Flat and Row prepare a bed's soil. New beds start Flat.
- A Cover bed's cover crop is picked in Properties > COVER, or dragged
  onto the bed from the Seeds panel in Plant mode (cover crops are
  listed after the other seeds). Sown and Terminated are dates you set;
  Seed needed works out the seed from the bed's area. Plantings over a
  Cover bed plant nothing, and dropping seed or greenhouse plants on
  one says "Plantings over cover crops cannot be seeded". Grow's
  Growing section lists a Cover bed from Sown until Terminated, with a
  Terminated today button. Render shows it as prepared soil washed
  green until there is cover-crop art.
- For Row ground, Properties > GROUND > Border reserves a clear walkway
  inside the bed's outline. Row width, Spacing and Border use inches
  when drawing units are feet, and centimetres when drawing units are metres.
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
  rows (a wide row gets several lines, Between rows apart);
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
  options. In-row and Between rows are centre-to-centre distances, as
  seed catalogs give them: In-row between plants along a line, Between
  rows between neighbouring lines. They use inches with feet units and
  centimetres with metres.
- Both start at the variety's smallest recommended spacing. Type to
  change either for this planting. Plants keep half the closer spacing
  clear of bed edges and line ends.
- In Render, each plant is drawn at its crop's typical full-grown
  width, so a bed at catalog spacing fills in along the row. Those
  widths are judged from common growing guides (Johnny's gives only
  spacing) and only change the picture, never the count. Plants over Row ground follow the rows; over Flat ground
  they follow that bed's Direction (set in its Properties > GROUND).
  Plants (under Seed) shows how many fit. Sown and Transplanted are
  dates: click one to pick a day from the calendar. Sown alone means
  sown in place; adding Transplanted means it was started elsewhere and
  set out that day (the × clears it). Transplanted needs a Sown date and
  cannot be earlier. Either date makes the planting show in Grow,
  named after the planting layer, counting from Transplanted when set,
  otherwise from Sown. Changing the seed changes that sowing; removing
  the seed or deleting the layer removes it. The bin removes the seed.

## Grow: Sow and Transplant
- The switch at the top right of Grow picks Sow (seed sown in place)
  or Transplant (seed started in flats and pots). Grow remembers which
  one you left it on.
- Set Hardiness to your USDA zone. Last frost and First frost show the
  zone's typical dates in grey until you set your own with the pencil
  (see Seasons and winter growing).
- Sow is for sowing in place; seed started in trays is in Transplant.
  Plan first: you can only sow plantings already on the map (Plan >
  Plant mode, a planting with a seed and nothing sown yet).
- The calendar has two sections. Growing, on top, is everything in the
  ground: sown in place, or planted out of Transplant ("Planted out
  <date>"), with germination in grey and harvest in red. Upcoming, below and faded, is
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
  planting's In-row, Between rows and Lines in Plan.
- The double tick (Harvest finished) on a Growing row takes it off the
  calendar once picking is done; the bin removes the sowing entirely.

## Seasons and winter growing
- Every growing calendar shades the frost-free season (last frost to
  first frost) in pale green behind the rows. Green LAST FROST and
  FIRST FROST markers, styled like TODAY, mark where each season starts
  and ends.
- The climate bar shows Last frost, First frost and Latitude as text
  with a pencil. Edit a frost date with its month and day dropdowns,
  then the tick to apply (× cancels); the reset arrow goes back to the
  zone's date. Edit Latitude by typing the degrees (e.g. 42.3) and
  picking N or S; the reset arrow clears it.
- Set the farm's Latitude to see winter options. They are timed from the last day with 10
  hours of daylight, which depends on latitude, so they stay hidden
  without it. Days never drop under 10 hours within about 32° of the equator.
- Winter options come from Johnny's Winter Growing Guide charts and
  cover about 25 cool-season crops (spinach, kale, lettuce, carrots,
  arugula, chicory and others). Crops the charts don't cover show only
  their usual windows.
  - Winter harvest: sown late summer or fall, harvested through winter;
    needs a high tunnel.
  - Overwinter: sown in fall, left in place for the earliest spring
    harvest; needs a low tunnel.
- On the calendar these are outlined, hatched bars on the variety's own
  row ("Needs tunnel" in the legend). The row text and the bar's tooltip
  say which option it is, what it needs, and Johnny's reliability tier.
- Rows and Start next describe each variety's soonest window, which may
  be a winter one.

## Planting lines
- A planting over Row ground has Lines in its GROW properties: how many
  lines of plants go along each row. All (the default) fills the row
  with as many as fit; type a number, or use the arrows, to plant fewer.
- The most you can enter is what fits across the row at the planting's
  Between rows spacing ("At most 5 lines fit. Reduce Between rows for
  more"). Widening Between rows later lowers Lines to the new most. Over Flat ground plants form a grid and Lines
  is greyed.

## Transplant
- The calendar has two sections. Growing, on top, is each flat or pot
  in the greenhouse, with its germination bar (grey) and the dates it
  can be planted out (blue); chips show Growing, Ready or Overdue.
  Upcoming, below and faded, is seed to start within a year, with
  its start window (amber).
- Both sections run soonest first: Growing by when it is ready to plant
  out, Upcoming by when the best start time begins.
- The arrow button (Planted out today) moves the tray into the ground.
- Start next: trays to start within a year.

Everything in these tools is saved in this browser as you go.

## Updating the crop catalog
Run `python3 tools/johnnys-catalog/scrape.py` for growing defaults and
`python3 tools/johnnys-catalog/scrape_varieties.py --refresh` for named varieties,
then rebuild the app. The variety list is a bundled catalog snapshot, not live
stock availability. Some crops and cultivation-specific categories have no
separately listed varieties. See
`tools/johnnys-catalog/README.md`.

## Flats and pots
- Transplant's Start next lists seed to start within a year. Its
  start button opens the dialog with that seed already chosen. Add plant
  (top of Start next) starts anything else; pick the seed in the dialog.
  Trays do not need a planting first: drag them onto one in
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
- Sow and Transplant show today's date above the months.
  Over the calendar, scroll the mouse wheel to zoom in (fewer days,
  day numbers appear) or out (up to about three years); drag left or
  right to move earlier or later, up or down to move through the list.
  Over the names the wheel scrolls the list. Today brings the view
  back. Darker lines mark the
  start of each week (Monday), fainter ones each day; zoomed far out,
  the darker lines mark months.
