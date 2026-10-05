#!/usr/bin/env python3
"""Winter planting windows from Johnny's Winter Growing Guide charts.

Johnny's publishes two charts, both timed in weeks BEFORE the last day
with 10 hours of daylight at the grower's latitude (the start of the
"Persephone period"):

  * Planting Dates for Winter-Harvest Crops: sown late summer/fall,
    harvested through winter, primarily in an unheated high tunnel.
  * Planting Dates for Overwintering for Spring Harvest: sown in fall,
    left in place (often under low tunnels) for the earliest spring crop.

Each chart row says whether to start transplants and/or direct seed, and
which week columns to sow in. This module parses both charts and attaches
the windows to the matching catalog crops as ``winterWindows``.

Run on its own to add the windows to the existing crops.json without
refetching every crop page:

    python3 tools/johnnys-catalog/winter_charts.py [--refresh] [--cache DIR]

scrape.py calls ``attach`` too, so a full rebuild keeps them.

Python 3 standard library only.
"""

import argparse
import datetime
import html
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import scrape  # noqa: E402  (fetch, publish_outputs, paths)

BASE = ("https://www.johnnyseeds.com/growers-library/methods-tools-supplies/"
        "winter-growing-season-extension/")
SOURCE = "Johnny's Selected Seeds — Winter Growing Guide planting charts"

# (use, page, structure): the structure is the protection the chart assumes.
CHARTS = [
    ("winterHarvest", BASE + "winter-harvest-planting-chart.html", "highTunnel"),
    ("overwinter", BASE + "overwintering-planting-chart.html", "lowTunnel"),
]

# Chart row name -> (catalog crop ids, detail shown with the window).
# Rows name a crop, sometimes with a harvest stage or a type. Every row
# must be listed: an unknown row fails the run, so a changed chart is
# noticed rather than silently dropped. An empty id list means the
# catalog has no such crop.
ROWS = {
    "Kale (Full)": (["kale"], None),
    "Kale (Baby)": (["kale"], "baby leaf"),
    "Tatsoi (Full)": (["asian-greens"], "tatsoi"),
    "Spinach (Full)": (["spinach"], None),
    "Spinach (Baby)": (["spinach"], "baby leaf"),
    "Spinach (Full/Baby)": (["spinach"], None),
    "Claytonia (Full)": (["claytonia"], None),
    "Baby Leaf Brassicas": (["baby-leaf-brassicas"], None),
    "Chicory (Cichorium intybus)": (
        ["radicchio", "italian-dandelion-chicory", "chicory-baby-leaf"], None),
    "Pac Choi (Full)": (["pac-choi"], None),
    "Cilantro (Full)": (["cilantro-coriander"], None),
    "Cilantro (Baby)": (["cilantro-coriander"], "baby leaf"),
    "Broccoli Raab": (["broccoli-raab"], None),
    "Choi Sum": ([], None),
    "Wild Arugula (Diplotaxis tenuifolia)": (["arugula"], "wild arugula"),
    "Salad Arugula (Eruca sativa)": (["arugula"], "salad arugula"),
    "Mizuna (Baby)": (["asian-greens"], "mizuna, baby leaf"),
    "Carrots": (["carrots", "pelleted-carrots"], None),
    "Bunching Onions (Scallions)": (["bunching-onions"], None),
    "Bunching Onions": (["bunching-onions"], None),
    "Spring Onions": (["onions", "pelleted-onions"], None),
    "Lettuce (Full)": (["lettuce", "pelleted-lettuce"], None),
    "Lettuce (Baby)": (["lettuce", "pelleted-lettuce"], "baby leaf"),
    "Swiss Chard (Full)": (["swiss-chard"], None),
    "Swiss Chard (Baby)": (["swiss-chard", "baby-leaf-swiss-chard"],
                           "baby leaf"),
    "Turnips": (["turnips"], None),
    "Radishes": (["radishes"], None),
    "Mâche": (["mache"], None),
}

TIER = re.compile(r"Tier\s*(\d)", re.I)


def _cell_text(cell):
    s = re.sub(r"<[^>]+>", "", cell)
    s = html.unescape(s).replace("\xa0", " ")
    return re.sub(r"\s+", " ", s).strip()


def _row_name(name):
    """'Broccoli Raab*' -> 'Broccoli Raab'; collapses doubled spaces."""
    return re.sub(r"\s+", " ", name.replace("*", "")).strip()


def parse_chart(page):
    """Rows of one chart: name, methods, weeks before the last 10-hour day
    (sorted, most weeks first), and tier.

    The table's header row is images whose alt text names the columns:
    CROP, Start Transplant, Direct Seed, Week N ... Week 1, 10-hour day.
    The first row of each tier group has an extra leading cell for the
    tier label, so rows are aligned on the column count.
    """
    tables = re.findall(r"(?is)<table.*?</table>", page)
    if len(tables) != 1:
        raise ValueError(f"expected one chart table, found {len(tables)}")
    table = tables[0]
    headers = [a.strip() for a in re.findall(r'alt="([^"]+)"', table)]
    try:
        first = next(i for i, h in enumerate(headers) if h.upper() == "CROP")
    except StopIteration:
        raise ValueError("chart has no CROP column") from None
    cols = []
    for h in headers[first:]:
        if re.match(r"(?i)tier", h):
            break
        cols.append(h)
    weeks = [int(m.group(1)) if (m := re.match(r"(?i)week\s*(\d+)", h)) else None
             for h in cols]
    if cols[1:3] != ["Start Transplant", "Direct Seed"] or not any(weeks):
        raise ValueError(f"unexpected chart columns: {cols}")

    rows, tier = [], None
    for raw in re.findall(r"(?is)<tr.*?</tr>", table):
        cells = [_cell_text(c) for c in
                 re.findall(r"(?is)<t[dh][^>]*>(.*?)</t[dh]>", raw)]
        joined = " ".join(cells)
        if (m := TIER.search(raw)) and not any(c == "✔" for c in cells):
            tier = int(m.group(1))
        if len(cells) == len(cols) + 1:
            # The tier label cell leads the first row of each group.
            if (m := TIER.search(raw)):
                tier = int(m.group(1))
            cells = cells[1:]
        if len(cells) != len(cols) or not cells[0] or "✔" not in joined:
            continue
        found = sorted({w for w, c in zip(weeks, cells)
                        if w is not None and c.strip().isdigit()},
                       reverse=True)
        if not found:
            raise ValueError(f"row {cells[0]!r} has no sowing weeks")
        rows.append({
            "name": _row_name(cells[0]),
            "transplant": cells[1] == "✔",
            "direct": cells[2] == "✔",
            "weeks": found,
            "tier": tier,
        })
    if not rows:
        raise ValueError("chart has no crop rows")
    return rows


def _runs(weeks):
    """[9, 8, 6, 5] -> [[9, 8], [6, 5]]: unbroken stretches of weeks."""
    runs = []
    for w in weeks:
        if runs and runs[-1][-1] == w + 1:
            runs[-1].append(w)
        else:
            runs.append([w])
    return runs


def windows_for(use, structure, row):
    """One window per sowing method of a chart row.

    A row ticked for both methods with two separate runs of weeks (e.g.
    broccoli raab: 9–8 and 6–5) gives the earlier run to starting
    transplants and the later to direct seeding, as the chart's footnote
    says. Otherwise every ticked method shares all the weeks.
    """
    runs = _runs(row["weeks"])
    methods = [m for m in ("transplant", "direct") if row[m]]
    split = len(methods) == 2 and len(runs) == 2
    out = []
    for i, method in enumerate(methods):
        weeks = runs[i] if split else row["weeks"]
        out.append({
            "use": use,
            "structure": structure,
            "method": method,
            "weeksBefore": [min(weeks), max(weeks)],
            "tier": row["tier"],
        })
    return out


def attach(crops, charts):
    """Give each crop in [crops] its ``winterWindows`` from [charts], a list
    of (use, structure, rows). Replaces any windows from an earlier run.
    Raises on a chart row ROWS does not know, or a mapped id that is not
    in the catalog."""
    by_id = {c["id"]: c for c in crops}
    for c in crops:
        c["winterWindows"] = []
    for use, structure, rows in charts:
        for row in rows:
            if row["name"] not in ROWS:
                raise ValueError(f"unknown chart row {row['name']!r} ({use})")
            ids, detail = ROWS[row["name"]]
            for crop_id in ids:
                if crop_id not in by_id:
                    raise ValueError(f"{row['name']!r} maps to missing crop "
                                     f"{crop_id!r}")
                for w in windows_for(use, structure, row):
                    if detail:
                        w["detail"] = detail
                    by_id[crop_id]["winterWindows"].append(w)
    return crops


def fetch_charts(cache, refresh=False):
    return [(use, structure, parse_chart(scrape.fetch(url, cache, refresh)))
            for use, url, structure in CHARTS]


def main():
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n\n")[0])
    ap.add_argument("--refresh", action="store_true", help="refetch the charts")
    ap.add_argument("--cache", type=Path, default=scrape.DEFAULT_CACHE)
    ap.add_argument("--out", type=Path, default=scrape.DEFAULT_OUT,
                    help="crops.json to add the windows to")
    args = ap.parse_args()

    catalog = json.loads(args.out.read_text(encoding="utf-8"))
    charts = fetch_charts(args.cache, args.refresh)
    attach(catalog["crops"], charts)
    catalog["winterSource"] = SOURCE
    catalog["winterFetched"] = datetime.date.today().isoformat()
    scrape.publish_outputs([(args.out, json.dumps(
        catalog, indent=2, ensure_ascii=False) + "\n")])
    with_windows = sum(1 for c in catalog["crops"] if c["winterWindows"])
    rows = sum(len(r) for _, _, r in charts)
    print(f"{rows} chart rows -> winter windows on {with_windows} crops "
          f"in {args.out}")


if __name__ == "__main__":
    main()
