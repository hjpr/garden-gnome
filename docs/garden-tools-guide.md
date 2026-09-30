# Garden tools guide

Garden Gnome opens on Home, which shows five tools: Build, Seed Vault,
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
- To filter the list, type in Search varieties or use the chips
  (Vegetables, Herbs, Cool, Warm, Transplant, Direct sow).

## Build: Ground and Plant
- Ground tool functions: Zone clears a zone back to plain dirt; Flat and
  Row prepare its soil; Grow makes it a grow zone.
- For Row ground, Properties > GROUND > Border reserves a clear walkway
  inside the zone's outline. Row width, Spacing and Border use inches
  when drawing units are feet, and metres when drawing units are metres.
  Enter 60 inches for a five-foot perimeter path. Rows shorten or split to follow
  uneven edges, curves and holes, keeping their full width clear of the
  border. Bordered rows are centred, sharing leftover space equally at
  opposite edges rather than adding it all to one side. The border is a
  minimum clearance; row widths and spacing are kept as entered.
  Row and plant counts update without changing the zone shape.
  Zero keeps the existing edge-to-edge layout; if no rows fit, the count
  is zero. Border changes are saved with the drawing and support Undo.
- A grow zone is drawn over Flat or Row zones on the same property to
  say what is planted there. It follows the soil under it: over Row
  ground, plants go only along the rows (a wide row gets several lines
  separated by Size plus Spacing); over Flat ground, they go on a grid
  running the grow zone's Direction; over plain dirt, nothing is
  planted.
- If soil zones overlap, the topmost Flat or Row zone in Layers wins.
  Its paths and borders stay unplanted; holes reveal the soil below.
  Overlapping zones do not duplicate plants or inflate the count.
- The Build | Plant switch in the header changes mode. Plant locks
  all geometry. Select picks existing grow zones without moving or
  reshaping them. Add, remove, or reshape zones in Build instead.
- Plant shows Drawing tools (Select only) and Seeds on the left, with
  Properties and Layers on the right. Operations and Controls return
  when you switch back to Build.
- Undo and Redo still work for planting changes, but layout changes
  require switching back to Build.
- In Plant mode the Seeds panel lists your Seed Vault. Drag a seed onto
  a grow zone to plant it (the zone lights up green where it would
  land), or click a seed to plant the selected grow zone.
- Only grow zones show Properties > PLANTING; they do not show ground
  options. Size is the plant diameter, and Spacing is the empty gap
  between plants. Plant centres are Size + Spacing apart, along rows
  and between planting lines. Zero spacing lets neighbouring plants
  touch. Changing spacing updates the layout and Plants count, including
  on a single row, without changing the plant diameter.
- Size starts at the variety's minimum in-row recommendation; Spacing
  starts at its minimum between-row recommendation minus Size, or zero
  if that difference is negative. Type to change either for this zone.
  Direction controls the grid on flat ground. Plants shows how many fit;
  Planted on lists the soil types underneath. The bin removes the seed.

## Grow
- Set Hardiness to your USDA zone. Last frost and First frost show the
  zone's typical dates in grey; type your own to replace them (for
  example "Apr 20").
- The calendar lists what you can sow within two months either side of
  today: Direct sow in green, Start in greenhouse in amber. The solid
  part of each bar is the best time. Chips show Early, Ideal, Late or
  Upcoming. Turn on Closed to see windows that have just ended.
- The sprout button (Sow today) or the tray button (Start in greenhouse
  today) records a sowing.

## Greenhouse
- Growing now: each tray, with its germination bar (grey) and the dates
  it can be planted out (blue). Chips show Growing, Ready or Overdue.
- The arrow button (Planted out today) moves the tray into the ground.
- Start next: trays to start within two months.

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
