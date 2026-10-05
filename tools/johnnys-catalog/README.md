# Johnny's catalog scraper

Builds `flutter/assets/catalog/crops.json`, the crop list the app uses for planting calendars, from
Johnny's Selected Seeds "Key Growing Information" pages (vegetables and culinary herbs).

## Run

    python3 tools/johnnys-catalog/scrape.py

- Python 3 standard library only.
- Fetches politely (1 request per second) and caches raw HTML in
  `~/.hermes/cache/scratch/johnnys-kgi` (override with `JOHNNYS_CACHE`; `--cache DIR` takes precedence).
  Reruns use the cache; add `--refresh` to fetch again.
- `--out FILE` writes somewhere else; `--raw FILE` also writes the un-curated parse, handy for review.
- Rejects an empty index (including HTTP 200 bot-wall pages) and aborts on any
  index/crop fetch or parse failure; it never publishes a partial collection of
  discovered links. Every index must discover crops and every discovered crop
  must parse and pass validation (required fields, ranges min <= max, enums).
- Validates the complete curated collection **before** writing either output.
  Catalog and optional raw JSON are staged in unique sibling files, then each
  is atomically replaced. Fetch, parse, validation, and staging failures leave
  existing output bytes unchanged. If a later replacement fails, earlier
  replacements are rolled back. The two files are not a single crash-atomic
  transaction. `--raw` and `--out` must name different paths.

### Offline tests

Run all Python importer tests without fetching the site or changing bundled assets:

```sh
TMPDIR="${TMPDIR:-$HOME/.hermes/cache/scratch}" \
  python3 -m unittest discover -s tools/johnnys-catalog/tests -p 'test*.py' -v
```

Refresh safety tests require `TMPDIR` to point at a scratch directory. They
create and clean isolated subdirectories there and mock all HTTP responses.

## What it does

1. Reads the vegetable and herb index pages and follows each crop link. Mushrooms, microgreens,
   sprouts, shoots, rootstock and medicinal/ornamental herbs are skipped.
2. Cuts the KGI text out of each page and splits it into its labelled sections
   (`CULTURE`, `TRANSPLANTING`, `HARVEST`, ...). These are kept as the growing instructions.
3. Pulls numbers out of the text with regexes: germination days, weeks to transplant,
   spacing, sowing depth, soil temperature, succession interval, harvest window.
4. Merges `overrides.json`, the hand-curated values.

## Winter windows

`winter_charts.py` parses Johnny's two Winter Growing Guide charts
(winter-harvest planting and overwintering planting) and adds a
`winterWindows` list to each crop they cover: use (`winterHarvest` or
`overwinter`), structure the chart assumes (`highTunnel` or
`lowTunnel`), method (`transplant` or `direct`), weeks before the last
10-hour day, Johnny's reliability tier, and an optional detail such as
"baby leaf". Chart rows are mapped to catalog crops in its `ROWS` table;
an unknown row fails the run. `scrape.py` runs it as part of a full
rebuild; to add the windows to the current crops.json alone:

    python3 tools/johnnys-catalog/winter_charts.py [--refresh]

## Cover crops

`cover_crops.py` builds `flutter/assets/catalog/cover_crops.json` (crops and
their varieties) from Johnny's Cover Crop Comparison Chart PDF (one crop per
chart row: sowing season, minimum germination temperature, hardiness zone,
growth rate, seeding rates, depth, benefits), the cover-crop Key Growing
Information pages (growing notes, shared where one page covers several
rows) and the `/cover-crops/` product listings (varieties with product
URLs). Nothing is estimated; cover crops stay out of the planting calendars.

    python3 tools/johnnys-catalog/cover_crops.py [--refresh]

Needs `pdftotext` (poppler-utils) for the chart. Chart rows map to crop ids
in `ROWS` and products to crop ids in `PRODUCTS`; an unknown row or product
fails the run. Products with no chart row (Berseem and Dutch White Clover,
Japanese Millet) are left out. Cache: `~/.hermes/cache/scratch/johnnys-cover-crops`.

Snapshot 2026-10-03: 26 cover crops and 34 varieties.

## Estimated values

Johnny's pages don't give everything the app needs (season, frost tolerance, planting window
relative to last frost, days to maturity, harvest window), and some parsed numbers are wrong.
Those were filled or corrected by horticultural judgement in `overrides.json`. Each crop's
`estimated` list names the fields that came from judgement rather than the page, so treat
them as reasonable defaults, not Johnny's figures.

To change a value, edit `overrides.json` and rerun the script.

## Seed Vault variety catalog

`scrape_varieties.py` independently builds `flutter/assets/catalog/varieties.json`
from Johnny's **real public product listings**, not from a hand-written variety
list. It reads (but never changes) `crops.json`. Python 3 standard library only.

```sh
# Refresh from the live source (at most one request per second, serially).
python3 tools/johnnys-catalog/scrape_varieties.py --refresh

# Rebuild using the cached source HTML; useful for reproducibility/debugging.
python3 tools/johnnys-catalog/scrape_varieties.py

# Deterministic offline parser, mapping, dedupe and pagination tests.
python3 -m unittest discover -s tools/johnnys-catalog/tests -p test_varieties.py -v
```

The variety importer explicitly uses
`~/.hermes/cache/scratch/johnnys-varieties` (on the development machine:
`/home/hjpr/.hermes/cache/scratch/johnnys-varieties`). Both importers use
profile-neutral defaults. `--cache DIR`, `--crops FILE`, `--out FILE`,
and `--report FILE` are supported. Its default `report.json` stays in that cache
and records every fetched listing/count, all source product IDs, display names,
secondary crop labels, descriptions and URLs, rejected products, covered IDs,
and missing IDs. Raw HTML remains cached beside it. Do not commit the cache.

### Source, mapping and completeness

- Starts at <https://www.johnnyseeds.com/vegetables/> and
  <https://www.johnnyseeds.com/herbs/>. Discovers relevant top-level category
  URLs from the site's navigation, using the existing KGI crop parent paths.
  Explicit category aliases cover source spelling differences (e.g.
  `artichokes` → `artichoke`, `arugula-roquette` → `arugula`) and the source's
  combined squash/separate salsify and scorzonera categories.
- Fetches each complete category listing (`sz=1000`), checks its declared
  product total, and follows offsets if the server paginates. Missing counts,
  incomplete tiles, repeated pages, or changing totals fail the import rather
  than publishing a silently truncated catalog. Any network failure also
  aborts before replacing the bundled file.
- Reads the source's `data-pid`, visible variety name, and product URL from
  product tiles. `id` is the **unaltered source product ID**, including any
  alphabetic suffix; it is not an invented slug or an index.
- Uses the most specific source category or an explicit crop label in the
  product's name/secondary label/description. For example, source-labeled
  Kabocha, Patty Pan, broccoli raab, and filet beans map to those existing crop
  IDs. It does not infer a crop from a cultivar name such as `Tobago` alone.
  Unclassified items stay out of the output. Actual named seed mixes remain;
  tools, rootstocks, microgreens, product bundles/collections and unrelated
  ornamental products do not.
- Deduplicates by crop + case-insensitive variety name. Numeric source IDs
  take priority over suffixed organic/treatment IDs, then lexical ID/URL order
  provides deterministic tie-breaking. Only source form labels (`Primed`,
  trailing `Plants`, `Early Ship`, `Fall-Planted`, `Spring-Planted`) are removed
  from names; meaningful strain names are retained. IDs and product links are
  never rewritten. Organic, pelleted and other treatments are **not distinct
  cultivars**; pelleted products map to the ordinary crop, not a duplicate
  `pelleted-*` growing-instruction entry.
- A product maps to one crop ID, not every compatible growing technique.
  Greenhouse and baby-leaf growing instructions may overlap ordinary crops;
  lack of a separate variety entry for a technique does not mean that crop
  cannot be grown that way. No stock/checkout API is queried: inclusion means
  listed in the public catalog, **not guaranteed in stock**.
- `fetched` is the ISO catalog build date. Without `--refresh`, HTML may be
  older; use `--refresh` for a current source snapshot. Cached same-day reruns
  are byte-for-byte deterministic. All IDs, names, crop references and
  source-ID URL suffixes are validated before atomic replacement.

### Verified snapshot: 2026-09-29

The live run fetched **81 category listings**, checked all page totals, and
collected **1,519 distinct source product IDs**. After exclusions and cultivar
deduplication it produced **1,182 varieties covering 127 of 146 crop IDs**, with
zero duplicate IDs, zero duplicate crop/name pairs and zero unknown crop IDs.
Offline tests use clearly marked synthetic HTML fixtures, not fake source data.

The following **19 crop IDs have no separately mapped varieties**:

```text
anise
baby-leaf-brassicas
baby-leaf-swiss-chard
caraway
chicory-baby-leaf
flower-sprouts
greenhouse-cucumbers
greenhouse-eggplants
greenhouse-peppers
greenhouse-tomatoes
leaf-broccoli
magenta-spreen
pelleted-beets
pelleted-carrots
pelleted-fennel
pelleted-lettuce
pelleted-onions
pelleted-parsnips
purslane
```

Pelleted/greenhouse/baby-leaf IDs are intentionally not manufactured by copying
ordinary varieties. The current flower-sprout product is categorized under
`kalettes`. Additional public site searches for `anise`, `caraway`, `purslane`,
`magenta spreen`, and `leaf broccoli` found no additional ordinary garden
products: anise returned Anise Hyssop, purslane returned a microgreen product,
and the other three returned no product tiles. These searches were exploratory
checks, not extra data sources required to rebuild the snapshot. Future source
changes can alter coverage; the refresh report always enumerates missing IDs.
