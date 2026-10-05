#!/usr/bin/env python3
"""Build flutter/assets/catalog/crops.json from Johnny's Selected Seeds
"Key Growing Information" (KGI) pages.

Steps:
  1. Read the vegetable and herb KGI index pages and collect crop page links.
  2. Fetch each crop page (1 request/second, cached in the scratch dir).
  3. Cut out the KGI block, split it into its labelled sections
     ("CULTURE:", "TRANSPLANTING:", ...) and pull numbers out with regexes.
  4. Merge hand-curated values from overrides.json.
  5. Validate and write the JSON.

Usage:
  python3 tools/johnnys-catalog/scrape.py [--refresh] [--cache DIR] [--out FILE]

Python 3 standard library only.
"""

import argparse
import datetime
import hashlib
import html
import json
import os
import re
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
DEFAULT_OUT = REPO / "flutter" / "assets" / "catalog" / "crops.json"
OVERRIDES = HERE / "overrides.json"
DEFAULT_CACHE = Path(
    os.environ.get("JOHNNYS_CACHE")
    or Path.home() / ".hermes/cache/scratch/johnnys-kgi"
)

SOURCE = "Johnny's Selected Seeds — Key Growing Information"
UA = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)
INDEXES = [
    ("Vegetables", "https://www.johnnyseeds.com/growers-library/vegetables/"
                   "key-growing-information-vegetables-index.html"),
    ("Herbs", "https://www.johnnyseeds.com/growers-library/herbs/"
              "key-growing-information-herbs-index.html"),
]
# Link path fragments we leave out: not garden crops, or not culinary herbs.
SKIP = [
    "/mushrooms/", "/microgreens/", "/sprouts/", "/shoots/",
    "rootstock", "/flowers/",
    # herbs that are medicinal/ornamental rather than culinary
    "angelica", "catmint", "catnip", "ginseng", "goldenseal", "rue-",
    "valerian", "white-sage", "mountain-mint", "bee-balm", "echinacea",
]

# ---------------------------------------------------------------- fetching

_last_request = [0.0]


def fetch(url, cache_dir, refresh=False):
    """Return page HTML, from cache when possible (polite: 1 request/s)."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    name = re.sub(r"[^A-Za-z0-9.-]+", "_", url.split("//", 1)[-1])[-120:]
    name += "-" + hashlib.sha1(url.encode()).hexdigest()[:8]
    path = cache_dir / name
    if path.exists() and not refresh:
        return path.read_text(encoding="utf-8")
    wait = 1.0 - (time.time() - _last_request[0])
    if wait > 0:
        time.sleep(wait)
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "en-US,en;q=0.9",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode("utf-8", "replace")
    finally:
        _last_request[0] = time.time()
    path.write_text(body, encoding="utf-8")
    return body


def crop_links(index_html):
    links = re.findall(r'href="(https://www\.johnnyseeds\.com/growers-library/'
                       r'[^"]*-key-growing-information\.html)"', index_html)
    out = []
    for u in links:
        if u in out or any(s in u for s in SKIP):
            continue
        out.append(u)
    return out

# ---------------------------------------------------------------- parsing


def to_text(fragment):
    """HTML fragment -> plain text with normalised whitespace."""
    s = re.sub(r"(?s)<!--.*?-->", " ", fragment)
    s = re.sub(r"(?is)<(script|style)\b.*?</\1>", " ", s)
    s = re.sub(r"(?i)<br\s*/?>|</p>|</li>|</h\d>|<h\d[^>]*>", " ", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s).replace("\xa0", " ")
    return re.sub(r"\s+", " ", s).strip()


START, STOP = "\x01", "\x02"   # label markers used while splitting


def kgi_block(page):
    """Return (title, marked body) of the KGI content, site nav stripped.

    Section labels (``<h2>CULTURE:</h2>`` or a bold span ``Culture:``) are
    wrapped in START/STOP markers so split_sections can cut on them.
    """
    at = page.find("c-culture")
    m = re.search(r"(?is)<h1[^>]*>(.*?)</h1>", page[at:])
    if at < 0 or not m:
        raise ValueError("no KGI heading")
    title = to_text(m.group(1))
    start = at + m.end()
    end = page.find("End content-asset", start)
    frag = page[start:end if end > 0 else start + 60000]
    frag = re.sub(r"(?s)<!--.*?(-->|$)", " ", frag)
    frag = re.sub(r"(?is)<h[23][^>]*>(.*?)</h[23]>",
                  lambda m: START + to_text(m.group(1)) + STOP, frag)
    bold = (r"(?is)<(span|strong|b)\b([^>]*)>((?:[^<\x01\x02]|<br\s*/?>)*?)</\1>")

    def mark_bold(m):
        tag, attrs, inner = m.groups()
        is_bold = tag.lower() in ("strong", "b") or "bold" in attrs.lower()
        text = to_text(inner)
        if is_bold and text.endswith(":") and 2 < len(text) < 60:
            return START + text + STOP
        return m.group(0)
    frag = re.sub(bold, mark_bold, frag)
    text = to_text(frag.replace(START, " " + START).replace(STOP, STOP + " "))
    return title, text


def split_sections(body):
    """Split marked body text into [{'title','text'}] in page order."""
    sections = []
    parts = re.split("\x01(.*?)\x02", body)
    lead = parts[0].strip()
    if lead:
        sections.append({"title": "OVERVIEW", "text": lead})
    for i in range(1, len(parts), 2):
        title = re.sub(r"\s+", " ", parts[i]).strip().rstrip(":").strip().upper()
        text = parts[i + 1].strip() if i + 1 < len(parts) else ""
        if not title:
            if sections:
                sections[-1]["text"] = (sections[-1]["text"] + " " + text).strip()
            continue
        sections.append({"title": title, "text": text})
    # a label with no text of its own belongs to the next label's text only
    return [s for s in sections if s["text"] or s["title"] != "OVERVIEW"]


# ---------------------------------------------------------------- numbers

DASH = r"\s*(?:–|-|—|to)\s*"
NUM = r"(\d+(?:\.\d+)?(?:\s+\d/\d)?|\d/\d)"


def num(s):
    s = s.strip()
    total = 0.0
    for part in s.split():
        if "/" in part:
            a, b = part.split("/")
            total += float(a) / float(b)
        else:
            total += float(part)
    return int(total) if total == int(total) else round(total, 3)


def rng(m, a=1, b=2):
    lo = num(m.group(a))
    hi = num(m.group(b)) if m.group(b) else lo
    return [min(lo, hi), max(lo, hi)]


def find_range(text, pattern):
    m = re.search(pattern, text, re.I)
    return rng(m) if m else None


def sec(sections, *keys):
    """Joined text of every section whose title contains one of keys."""
    return " ".join(s["text"] for s in sections
                    if any(k in s["title"] for k in keys))


def first_range(text, pattern, lo=None, hi=None):
    """First regex match whose range lies inside [lo, hi]."""
    for m in re.finditer(pattern, text, re.I):
        v = rng(m)
        if (lo is None or v[0] >= lo) and (hi is None or v[1] <= hi):
            return v, m
    return None, None


def scientific_name(text):
    if not text:
        return None
    # stop at a sentence end but keep abbreviations like 'var.' and 'spp.'
    m = re.match(r"(.*?)(?<!var)(?<!spp)(?<!sp)(?<!ssp)(?<!subsp)(?<!\b[A-Z])\.(?:\s|$)",
                 text + " ")
    name = (m.group(1) if m else text).strip().rstrip(",;")
    if len(name) > 70 or not re.match(r"[A-Z][a-z]+ ", name):
        return None
    return name


INCH = r"(?:\"|''|”|″|\s*in\.?(?=[\s,;)])|\s*inch(?:es)?)"
FOOT = r"(?:'|’|′|\s*feet|\s*foot|\s*ft\.?)"
LEN = rf"{NUM}(?:{DASH}{NUM})?\s*({INCH}|{FOOT})"


def _inches(m):
    v = rng(m)
    if re.match(FOOT + "$", m.group(3)):
        v = [x * 12 for x in v]
    return v


def parse_numbers(sections, all_text):
    r = {}
    r["scientificName"] = scientific_name(
        sec(sections, "SCIENTIFIC NAME", "LATIN NAME", "BOTANICAL NAME"))

    germ = sec(sections, "DAYS TO GERMINATION")
    v, _ = first_range(germ, rf"{NUM}(?:{DASH}{NUM})?\s*days", 1, 60)
    if not v:
        v, _ = first_range(all_text, rf"(?:germinat\w*|emerge\w*)[^.]*?\b(?:in|within)\s+"
                           rf"(?:about\s+)?{NUM}(?:{DASH}{NUM})?\s*days", 1, 60)
    r["germinationDays"] = v

    v = None
    for pat in [rf"(?:ready to transplant|ready for transplant\w*)\s+in\s+(?:about\s+)?"
                rf"{NUM}(?:{DASH}{NUM})?\s*weeks",
                rf"transplant\w*(?:\s+outdoors)?\s+{NUM}(?:{DASH}{NUM})?\s*weeks\s+after\s+sowing",
                rf"{NUM}(?:{DASH}{NUM})?\s*weeks?\s+(?:before|prior to)\s+(?:transplant|"
                rf"setting|the (?:average )?last|last|average|your|moving|field planting|"
                rf"desired transplant|planting out)"]:
        for m in re.finditer(pat, all_text, re.I):
            if re.search(r"cultivat|crowns", all_text[max(0, m.start() - 60):m.start()], re.I):
                continue
            w = rng(m)
            if 2 <= w[0] and w[1] <= 16:
                v = w
                break
        if v:
            break
    r["weeksToTransplant"] = v

    # DAYS TO MATURITY sections usually say only 'From transplanting'; a number
    # there is normally the add/subtract adjustment, so only take stated ranges.
    dtm = sec(sections, "DAYS TO MATURITY")
    v, m = first_range(dtm, rf"(?<!add )(?<!subtract ){NUM}(?:{DASH}{NUM})?\s*days"
                       rf"(?!\s+(?:if|for days|from))", 20, 200)
    if m and re.search(r"(add|subtract)\w*\s*(about\s*)?$", dtm[:m.start()], re.I):
        v = None
    r["daysToMaturity"] = v
    low = dtm.lower()
    t = re.search(r"from (?:the )?(?:date of )?transplant", low)
    d = re.search(r"from (?:the )?(?:date of )?(?:direct )?(?:seeding|sowing|seed)", low)
    r["maturityFrom"] = (None if not (t or d) else "transplant" if t and (not d or t.start() < d.start())
                         else "seeding")

    m = re.search(rf"(?:every\s+{NUM}(?:{DASH}{NUM})?[- ](days?|weeks?)|"
                  rf"\b{NUM}(?:{DASH}{NUM})?[- ](days?|weeks?)\s+intervals)",
                  sec(sections, "SUCCESSION", "CULTURE", "DIRECT SEEDING", "SOWING",
                      "HEAD LETTUCE", "BABY LEAF", "TRANSPLANTING"), re.I)
    r["successionDays"] = None
    if m:
        g = m.groups()
        val, unit = (num(g[0]), g[2]) if g[0] else (num(g[3]), g[5])
        days = val * 7 if unit.lower().startswith("week") else val
        if 5 <= days <= 42:
            r["successionDays"] = int(days)

    between = None
    for pat in [rf"rows?\s+(?:spaced\s+|that are\s+|at least\s+|about\s+)*{LEN}\s*apart",
                rf"{LEN}\s*(?:apart\s+)?between\s+rows",
                rf"(?:in\s+rows|bands)\s+{LEN}"]:
        m = re.search(pat, all_text, re.I)
        if m:
            between = _inches(m)
            break
    r["betweenRowSpacingIn"] = between

    # In-row spacing, most specific wording first. Skip seedling-flat and
    # between-row distances.
    def ok(m):
        after = all_text[m.end(): m.end() + 30].lower()
        before = all_text[max(0, m.start() - 25): m.start()].lower()
        if re.search(r"between rows|flats|pots|cells?\b|trays|wide|band|tall|high|deep", after):
            return False
        if re.search(r"rows?\s+(?:that are\s+|at least\s+|spaced\s+)*$|bands?\s*$|beds\s*$", before):
            return False
        return _inches(m)[1] <= 72

    inrow = None
    v, _ = first_range(sec(sections, "PLANT SPACING"), rf"{NUM}(?:{DASH}{NUM})?\s*{INCH}", 0.5, 60)
    if v:
        inrow = v
    for pat in [rf"thin\w*\s+(?:\w+\s+){{0,3}}?to\s+(?:stand\s+|about\s+|1 plant (?:per|every)\s+)*{LEN}",
                rf"(?:space|spacing|spaced|set|transplant|plant)\w*\s+(?:\w+\s+){{0,3}}?(?:at\s+|about\s+)*"
                rf"{LEN}\s*(?:apart|spacing|between plants)",
                rf"{LEN}\s*between\s+plants",
                rf"{LEN}\s*apart"]:
        if inrow:
            break
        for m in re.finditer(pat, all_text, re.I):
            if ok(m):
                inrow = _inches(m)
                break
    r["inRowSpacingIn"] = inrow

    v, _ = first_range(all_text, rf"{NUM}(?:{DASH}{NUM})?\s*{INCH}\s*deep", 0.05, 6)
    r["sowingDepthIn"] = None if not v else (v[0] if v[0] == v[1] else round(sum(v) / 2, 3))

    v, _ = first_range(sec(sections, "DAYS TO GERMINATION", "DIRECT SEEDING", "TRANSPLANTING",
                           "SOWING", "CULTURE", "GROWING FROM SEED"),
                       rf"(?:soil|mix|germinat\w*|keep|at)[^.]*?{NUM}(?:{DASH}{NUM})?\s*°\s*F",
                       35, 95)
    r["soilTempF"] = v

    r["harvestWindowDays"] = None
    for sentence in re.split(r"(?<=\.)\s+", sec(sections, "HARVEST")):
        if re.search(r"cur(e|ing)|skin|stor|cooler|humidity|after planting|years?", sentence, re.I):
            continue
        m = re.search(rf"(?:harvest\w*|pick\w*|yield\w*)[^.]*?(?:over|for|period of)\s+"
                      rf"(?:about\s+|a\s+)?{NUM}(?:{DASH}{NUM})?\s*(weeks?|days)", sentence, re.I)
        if m:
            mult = 7 if m.group(3).lower().startswith("week") else 1
            r["harvestWindowDays"] = [int(x * mult) for x in rng(m)]
            break
    return r


def guess_sowing(sections):
    sow = sec(sections, "SOWING").lower()
    if sow:  # herb pages: "Direct seed (recommended)" / "Transplant (recommended)"
        has_d = "direct" in sow
        has_t = "transplant" in sow or "indoors" in sow
        return "either" if has_d and has_t else "direct" if has_d else \
            "transplant" if has_t else None
    titles = " ".join(s["title"] for s in sections)
    has_t = "TRANSPLANT" in titles
    has_d = "DIRECT SEED" in titles or "DIRECT SOW" in titles
    if has_t and has_d:
        return "either"
    if has_t:
        return "transplant"
    if has_d:
        return "direct"
    return None

# ---------------------------------------------------------------- building

FIELDS = ["scientificName", "season", "frostTolerance", "sowing", "germinationDays",
          "weeksToTransplant", "daysToMaturity", "maturityFrom", "plantOutWeeks",
          "fallCrop", "successionDays", "harvestWindowDays", "inRowSpacingIn", "betweenRowSpacingIn",
          "sowingDepthIn", "soilTempF", "overwinterWeeks"]
REQUIRED = ["season", "frostTolerance", "sowing", "plantOutWeeks", "daysToMaturity",
            "harvestWindowDays",
            "inRowSpacingIn", "betweenRowSpacingIn"]
RANGES = ["overwinterWeeks", "germinationDays", "weeksToTransplant", "daysToMaturity", "plantOutWeeks",
          "harvestWindowDays",
          "inRowSpacingIn", "betweenRowSpacingIn", "soilTempF"]


def build_crop(category, url, page):
    title, body = kgi_block(page)
    name = re.split(r"\s*[-–—]?\s*Key Growing", title)[0].strip()
    slug = url.rsplit("/", 1)[-1].replace("-key-growing-information.html", "")
    sections = split_sections(body)
    crop = {"id": slug, "name": name, "category": category, "url": url}
    nums = parse_numbers(sections, body)
    for f in FIELDS:
        crop[f] = nums.get(f)
    crop["sowing"] = guess_sowing(sections)
    if crop["sowing"] == "direct":
        crop["weeksToTransplant"] = None
    crop["fallCrop"] = bool(re.search(r"\bfall (crop|harvest|planting|sowing)|for fall|late[- ]summer|"
                                      r"overwinter", body, re.I))
    crop["sections"] = sections
    crop["estimated"] = []
    return crop


def apply_overrides(crop, overrides):
    """Merge curated values. Fields changed by judgement go into 'estimated'."""
    # Weeks around the first fall frost to plant crops that overwinter in
    # the ground (garlic); only ever set by hand in overrides.json.
    crop.setdefault("overwinterWeeks", None)
    ov = dict(overrides.get("defaults", {}))
    ov.update(overrides.get("crops", {}).get(crop["id"], {}))
    for k, v in ov.items():
        if k.startswith("_"):
            continue
        if k == "sections":
            continue
        if crop.get(k) != v:
            crop[k] = v
            if k in FIELDS and k not in crop["estimated"]:
                crop["estimated"].append(k)
    # direct-only crops have no transplant timing
    if crop["sowing"] == "direct" and crop["weeksToTransplant"] is not None:
        crop["weeksToTransplant"] = None
    crop["estimated"] = [f for f in FIELDS if f in crop["estimated"]]
    order = ["id", "name", "category", "url"] + FIELDS + ["sections", "estimated"]
    return {k: crop[k] for k in order}


def validate(crops):
    problems = []
    for c in crops:
        for f in REQUIRED:
            if c.get(f) in (None, [], ""):
                problems.append(f"{c['id']}: missing {f}")
        if c["sowing"] in ("transplant", "either") and not c["weeksToTransplant"]:
            problems.append(f"{c['id']}: missing weeksToTransplant")
        for f in RANGES:
            v = c.get(f)
            if v is not None and (len(v) != 2 or v[0] > v[1]):
                problems.append(f"{c['id']}: bad range {f}={v}")
        if c["season"] not in ("cool", "warm"):
            problems.append(f"{c['id']}: bad season {c['season']}")
        if c["frostTolerance"] not in ("tender", "half-hardy", "hardy"):
            problems.append(f"{c['id']}: bad frostTolerance")
        if c["sowing"] not in ("transplant", "direct", "either"):
            problems.append(f"{c['id']}: bad sowing")
        if not c["sections"]:
            problems.append(f"{c['id']}: no sections")
    return problems


def publish_outputs(outputs):
    """Stage beside targets; atomically replace each file, rolling back on error.

    Multiple files cannot be replaced as one filesystem transaction. Backups
    restore already-replaced files if a later replacement raises an exception.
    """
    targets = [target.resolve() for target, _ in outputs]
    if len(set(targets)) != len(targets):
        raise ValueError("Catalog and raw output paths must be different")
    temporary_paths, staged, committed = [], [], []

    def stage(target, data):
        with tempfile.NamedTemporaryFile(mode="wb", dir=target.parent,
                prefix=f".{target.name}.", delete=False) as stream:
            temporary = Path(stream.name)
            temporary_paths.append(temporary)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        return temporary

    try:
        for target, text in outputs:
            target.parent.mkdir(parents=True, exist_ok=True)
            backup = stage(target, target.read_bytes()) if target.exists() else None
            staged.append((stage(target, text.encode("utf-8")), target, backup))
        for temporary, target, backup in staged:
            os.replace(temporary, target)
            committed.append((target, backup))
    except Exception:
        for target, backup in reversed(committed):
            if backup is None:
                target.unlink()
            else:
                os.replace(backup, target)
        raise
    finally:
        for temporary in temporary_paths:
            temporary.unlink(missing_ok=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--refresh", action="store_true", help="refetch cached pages")
    ap.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--raw", type=Path, help="also write un-curated parse here")
    args = ap.parse_args()

    overrides = json.loads(OVERRIDES.read_text(encoding="utf-8")) if OVERRIDES.exists() else {}
    crops, raw = [], []
    for category, index_url in INDEXES:
        links = crop_links(fetch(index_url, args.cache, args.refresh))
        print(f"{category}: {len(links)} pages")
        if not links:
            print(f"No crop links (blocked or changed index): {index_url}", file=sys.stderr)
            sys.exit(1)
        for url in links:
            try:
                crop = build_crop(category, url, fetch(url, args.cache, args.refresh))
            except Exception as e:  # Never publish a partial collection.
                print(f"  ! {url}: {e}", file=sys.stderr)
                sys.exit(1)
            raw.append(json.loads(json.dumps(crop)))
            crops.append(apply_overrides(crop, overrides))

    crops.sort(key=lambda c: (c["name"].lower(), c["id"]))
    # Winter-harvest and overwintering windows from Johnny's winter charts.
    # Imported here: winter_charts imports this module for fetch().
    import winter_charts
    try:
        winter_charts.attach(crops, winter_charts.fetch_charts(args.cache, args.refresh))
    except Exception as e:  # Never publish a partial collection.
        print(f"  ! winter charts: {e}", file=sys.stderr)
        sys.exit(1)
    problems = validate(crops)
    if problems:
        print(f"{len(problems)} validation problems:", file=sys.stderr)
        for p in problems:
            print("  - " + p, file=sys.stderr)
        sys.exit(1)

    out = {"source": SOURCE, "fetched": datetime.date.today().isoformat(),
           "winterSource": winter_charts.SOURCE, "crops": crops}
    outputs = [(args.out, json.dumps(out, indent=2, ensure_ascii=False) + "\n")]
    if args.raw:
        outputs.append((args.raw, json.dumps(raw, indent=2, ensure_ascii=False) + "\n"))
    publish_outputs(outputs)

    n_est = sum(1 for c in crops if c["estimated"])
    print(f"Wrote {len(crops)} crops to {args.out}")
    print(f"  vegetables {sum(c['category'] == 'Vegetables' for c in crops)}, "
          f"herbs {sum(c['category'] == 'Herbs' for c in crops)}; "
          f"{n_est} with estimated fields")
    print("Validation OK")


if __name__ == "__main__":
    main()
