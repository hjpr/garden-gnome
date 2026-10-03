# Farm model

Agreed design for how Build, Seed Vault, Greenhouse, Grow and Harvest fit
together. Built: one farm, one file; climate and plantings in the farm;
last farm reopens; moving old data; Seed Vault export and import. Planting
layers' Sown and Transplanted dates write to the shared planting record
(linked by layer). Not built yet: picking a planting layer when planting
out a greenhouse tray, and the greenhouse layer.

## One farm, one file

- The open file is the farm. Build, Greenhouse, Grow and Harvest read and
  change only that farm.
- A farm can be split any way the gardener likes into property layers,
  beds, planting layers and reference images. It is still one farm.
- New gives a blank farm with empty calendars. Open switches farms;
  farms are never added together. A Save As copy is a separate farm.
- Other farms can be kept and switched to (a test farm, a second site);
  only the open one counts.
- The last farm open reopens at startup, so Home > Harvest shows it.

## What the farm file holds

- Land: properties, beds, plantings, reference images.
- Plantings and their dates (below).
- Climate: hardiness zone and frost dates, because they describe where
  the farm is.

Kept outside the file:

- The Seed Vault: one app-wide library of varieties, used by any farm.
  It can be exported and imported as its own file (built).
- View settings and preferences.

## One planting record

A planting has a seed (a Seed Vault variety), where it was started
(Greenhouse or In place), a Sown date, an optional Transplanted date and
an optional area on the map.

- Sown in place: Sown date and a map area.
- Started in the greenhouse: Sown date and no map area. It shows in
  Greenhouse. Transplanting gives it a Transplanted date and an area on
  the map (a planting layer drawn or picked).
- Harvest counts from the Transplanted date when there is one, otherwise
  from the Sown date.
- Finished plantings leave Harvest and stay in the file as history.

Each tool shows the same record: Build shows where and how many,
Greenhouse what is in trays, Grow what to do when for this farm's
climate, Harvest what is coming.

This replaces both the app-wide sowings list and the single Plant on date
on a planting layer.

## Greenhouse

A greenhouse tray exists without a map area until it is transplanted.
Planned: a visual greenhouse layer showing what is growing, giving trays
a "virtual" place before they go in the ground.

## Moving existing data

Sowings in the app-wide record move into the farm that is open the first
time the new version runs. Nothing is lost.
