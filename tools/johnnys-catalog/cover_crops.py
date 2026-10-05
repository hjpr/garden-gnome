#!/usr/bin/env python3
"""Cover crops and their varieties from Johnny's Selected Seeds.

Builds flutter/assets/catalog/cover_crops.json from three public sources:

  * the Cover Crop Comparison Chart (PDF): one crop per chart row, with
    its sowing season, minimum germination temperature, hardiness zone,
    growth rate, seeding rates, depth and benefits;
  * the cover-crop Key Growing Information pages: growing notes for the
    rows they cover (several rows share a page, e.g. Clovers & Alfalfa);
  * the /cover-crops/ product listings: the varieties, each with its
    product page, mapped to a chart row in PRODUCTS.

Nothing is estimated. Cover crops have no frost-relative window, plant
spacing or days to maturity on Johnny's, so the app keeps them out of
the planting calendars.

    python3 tools/johnnys-catalog/cover_crops.py [--refresh]

Python 3 standard library, plus poppler's `pdftotext` to read the chart.
"""

import argparse
import datetime
import json
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import scrape  # noqa: E402  (fetch, kgi parsing, publish_outputs)
from scrape_varieties import collect_listing  # noqa: E402

BASE = 'https://www.johnnyseeds.com/'
LISTINGS = BASE + 'cover-crops/'
KGI_INDEX = (BASE + 'growers-library/farm-seed-cover-crops/'
             'key-growing-information-farm-seed-index.html')
CHART_PAGE = (BASE + 'growers-library/farm-seed-cover-crops/'
              'farm-seed-comparison-chart-pdf.html')
SOURCE = "Johnny's Selected Seeds — Cover Crop Comparison Chart, cover crop Key Growing Information and product listings"
DEFAULT_CACHE = Path.home() / '.hermes/cache/scratch/johnnys-cover-crops'
DEFAULT_OUT = HERE.parent.parent / 'flutter/assets/catalog/cover_crops.json'

# Chart row -> (crop id, display name, KGI page slug or None). Every chart
# row must be listed: an unknown row fails the run, so a changed chart is
# noticed. A None page means Johnny's has no growing notes for it.
ROWS = {
    'Alfalfa, Summer': ('summer-alfalfa', 'Summer Alfalfa', 'clovers-alfalfa'),
    'Barley': ('barley', 'Barley', 'grains'),
    'Buckwheat': ('buckwheat', 'Buckwheat', 'buckwheat'),
    'Clover, Crimson': ('crimson-clover', 'Crimson Clover', 'clovers-alfalfa'),
    'Clover, Mammoth Red': ('mammoth-red-clover', 'Mammoth Red Clover', 'clovers-alfalfa'),
    'Clover, Medium Red': ('medium-red-clover', 'Medium Red Clover', 'clovers-alfalfa'),
    'Clover, New Zealand White': ('new-zealand-white-clover', 'New Zealand White Clover',
                                  'clovers-alfalfa'),
    'Clover, Sweet': ('sweet-clover', 'Sweet Clover', 'clovers-alfalfa'),
    'Manure Mix, Fall Green': ('fall-green-manure-mix', 'Fall Green Manure Mix',
                               'fall-green-manure-mix'),
    'Manure Mix, Spring Green': ('spring-green-manure-mix', 'Spring Green Manure Mix',
                                 'spring-green-manure-mix'),
    'Millet, Pearl': ('pearl-millet', 'Pearl Millet', None),
    'Mustard': ('mustard-cover-crop', 'Mustard', 'forage-crops-brassica-rapa'),
    'Oats, Common': ('common-oats', 'Common Oats', 'grains'),
    'Oats, Hulless': ('hulless-oats', 'Hulless Oats', 'grains'),
    'Peas and Oats Mix': ('peas-and-oats-mix', 'Peas and Oats Mix', 'peas-oats-mix'),
    'Peas, Field': ('field-peas', 'Field Peas', 'peas-cover-crop'),
    'Radish, Oilseed': ('oilseed-radish', 'Oilseed Radish', 'forage-crops-brassica-rapa'),
    'Rye, Winter': ('winter-rye', 'Winter Rye', 'winter-grains'),
    'Ryegrass': ('ryegrass', 'Ryegrass', 'ryegrass'),
    'Sudangrass': ('sudangrass', 'Sudangrass', None),
    'Sunflower': ('sunflower-cover-crop', 'Sunflower', 'sunflowers-cover-crop'),
    'Sunn Hemp': ('sunn-hemp', 'Sunn Hemp', 'sunn-hemp'),
    'Teff': ('teff', 'Teff', 'teff'),
    'Turnips, Purple Top': ('purple-top-turnips', 'Purple Top Turnips',
                            'forage-crops-brassica-rapa'),
    'Vetch, Hairy': ('hairy-vetch', 'Hairy Vetch', 'hairy-vetch-cover-crop'),
    'Wheat, Spring': ('spring-wheat', 'Spring Wheat', 'grains'),
}

# Product name pattern -> crop id; None leaves the product out because the
# chart has no row for it. Every seed product must match one pattern, or
# the run fails.
PRODUCTS = [
    (r'^(Yellow Mustard|Mighty Mustard.*)$', 'mustard-cover-crop'),
    (r'^Buckwheat\b', 'buckwheat'),
    (r'^Oilseed Radish$', 'oilseed-radish'),
    (r'^Purple Top Forage Turnips$', 'purple-top-turnips'),
    (r'Sunflower$', 'sunflower-cover-crop'),
    (r'^Winter Rye\b', 'winter-rye'),
    (r'^Oats \(Common\)$', 'common-oats'),
    (r'^Hulless Oats\b', 'hulless-oats'),
    (r'^Ryegrass$', 'ryegrass'),
    (r'^Spring Wheat\b', 'spring-wheat'),
    (r'^Barley\b', 'barley'),
    (r'^Hybrid Pearl Millet$', 'pearl-millet'),
    (r'^Japanese Millet$', None),
    (r'^Sudangrass\b', 'sudangrass'),
    (r'^Crimson Clover$', 'crimson-clover'),
    (r'^Hairy Vetch$', 'hairy-vetch'),
    (r'(Field Peas?\b.*|^DS Admiral Pea|^VNS Yellow Pea)', 'field-peas'),
    (r'^Dutch White Clover$', None),
    (r'^Berseem Clover$', None),
    (r'^New Zealand White Clover$', 'new-zealand-white-clover'),
    (r'^Medium Red Clover$', 'medium-red-clover'),
    (r'^Mammoth Red Clover$', 'mammoth-red-clover'),
    (r'^Sweet Clover$', 'sweet-clover'),
    (r'^Sunn Hemp$', 'sunn-hemp'),
    (r'^Summer Alfalfa$', 'summer-alfalfa'),
    (r'^Fall Green Manure Mix$', 'fall-green-manure-mix'),
    (r'^Peas and Oats Mix$', 'peas-and-oats-mix'),
    (r'^Spring Green Manure Mix$', 'spring-green-manure-mix'),
]

# Benefit columns, keyed by the first word of each rotated header.
BENEFITS = {
    'Nitrogen': 'Nitrogen fixation', 'Bees/Beneficial': 'Bees and beneficial insects',
    'Compaction': 'Compaction control', 'Erosion': 'Erosion control',
    'Weed': 'Weed suppression', 'Green': 'Green manure', 'Forage': 'Forage',
    'Biomass': 'Biomass',
}
# Data columns, keyed by the first word of each header.
COLUMNS = [('Sowing', 'sowingSeason'), ('Minimum', 'minGermTemp'),
           ('Hardiness', 'hardinessZone'), ('Growth', 'growthRate'),
           ('Sow', 'seedPer1000SqFt'), ('Sow', 'seedPerAcre'),
           ('Seeding', 'sowingDepth')]


# ---------------------------------------------------------------- chart

def chart_words(pdf_bytes):
    """Words with their boxes, from `pdftotext -bbox`."""
    exe = shutil.which('pdftotext')
    if not exe:
        raise RuntimeError('pdftotext (poppler-utils) is needed to read the chart PDF')
    with tempfile.TemporaryDirectory() as tmp:
        pdf = Path(tmp) / 'chart.pdf'
        pdf.write_bytes(pdf_bytes)
        out = subprocess.run([exe, '-bbox', str(pdf), '-'], check=True,
                             capture_output=True, text=True).stdout
    return parse_bbox(out)


def parse_bbox(text):
    import html
    return [(float(x0), float(y0), float(x1), html.unescape(w)) for x0, y0, x1, w in re.findall(
        r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="[\d.]+">([^<]*)</word>',
        text)]


def parse_chart(words):
    """Chart rows: {row name: {column: text, 'benefits': [...]}}."""
    def first(word, after=0.0):
        hits = sorted(w for w in words if w[3] == word and w[0] >= after)
        if not hits:
            raise ValueError(f'Chart header "{word}" not found (chart changed?)')
        return hits[0]
    # Data headers sit on one line; benefit headers are rotated above them.
    header_y = first('Sowing')[1]
    starts, after = [], 100.0
    for word, key in COLUMNS:
        hit = min((w for w in words if w[3] == word and w[0] > after
                   and abs(w[1] - header_y) < 10), key=lambda w: w[0], default=None)
        if hit is None:
            raise ValueError(f'Chart column "{word}" not found')
        starts.append((hit[0], key))
        after = hit[0] + 1
    top = max(w[1] for w in words if w[3] in ('Depth', 'Zone')) + 8
    # Benefit headers: in the header band, right of the data columns, so a
    # row name such as "Manure Mix, Fall Green" is never taken for one.
    header = [w for w in words if w[1] < top and w[0] > starts[-1][0]]
    benefit_x = []
    for word, name in BENEFITS.items():
        hit = min((w for w in header if w[3] == word), default=None)
        if hit is None:
            raise ValueError(f'Chart benefit column "{word}" not found')
        benefit_x.append((hit[0], name))
    benefit_x.sort()
    # The key line under the table ("† = Frost Seeding Suitable") ends it.
    bottom = min((w[1] for w in words if w[3] == '†' and w[0] < 40), default=None)
    if bottom is None:
        raise ValueError('Chart footnote not found')
    names_x = starts[0][0]
    # One line per row; words a point or so off (the "NEW" badge) join it.
    lines = []
    for y in sorted(w[1] for w in words if w[0] < names_x and top < w[1] < bottom):
        if not lines or y - lines[-1] > 4:
            lines.append(y)
    rows = {}
    for i, y in enumerate(lines):
        nxt = lines[i + 1] if i + 1 < len(lines) else bottom
        band = [w for w in words if y - 6 <= w[1] < nxt - 6]
        name = ' '.join(w[3] for w in sorted(band) if w[0] < names_x)
        name = re.sub(r'^NEW\s+', '', name).strip()
        row = {}
        for j, (x, key) in enumerate(starts):
            end = starts[j + 1][0] if j + 1 < len(starts) else benefit_x[0][0] - 2
            row[key] = ' '.join(w[3] for w in sorted(band) if x - 1 <= w[0] < end - 1)
        row['benefits'] = []
        for j, (x, label) in enumerate(benefit_x):
            mark = [w[3] for w in band if abs(w[0] - x) < 6]
            if mark:
                row['benefits'].append({'name': label, 'secondYear': '2Y' in mark})
        rows[name] = row
    return rows


def chart_crop(row_name, row):
    crop_id, name, _ = ROWS[row_name]
    season = row['sowingSeason']
    temp = re.match(r'(\d+)°F', row['minGermTemp'])
    if not temp or not season:
        raise ValueError(f'Unreadable chart row: {row_name}: {row}')
    zone = row['hardinessZone']
    return {
        'id': crop_id, 'name': name, 'chartRow': row_name,
        'sowingSeason': season.replace('†', '').strip(),
        'frostSeeding': '†' in season,
        'minGermTempF': int(temp.group(1)),
        # A USDA zone number, or Johnny's NFT (not frost tolerant) / Various.
        'hardinessZone': {'NFT': 'not frost tolerant'}.get(zone, zone),
        'growthRate': row['growthRate'],
        'seedPer1000SqFt': row['seedPer1000SqFt'],
        'seedPerAcre': row['seedPerAcre'],
        'sowingDepth': row['sowingDepth'],
        'benefits': row['benefits'],
    }


def chart_pdf_url(page):
    links = re.findall(r'href="(https://www\.johnnyseeds\.com/[^"]*farm-seed-comparison-chart\.pdf)"', page)
    if not links:
        raise ValueError('Comparison chart PDF link not found')
    return links[0]


def fetch_bytes(url, cache, refresh):
    path = cache / 'farm-seed-comparison-chart.pdf'
    if path.exists() and not refresh:
        return path.read_bytes()
    req = urllib.request.Request(url, headers={'User-Agent': scrape.UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
    if not data.startswith(b'%PDF'):
        raise ValueError(f'Not a PDF: {url}')
    cache.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return data


# ---------------------------------------------------------------- products

def map_product(row):
    """Crop id for a listing tile, None to leave it out. Fails if unknown."""
    if '/cover-crops/' not in row['url']:
        return None  # tools and supplies shown in the listings
    for pattern, crop_id in PRODUCTS:
        if re.search(pattern, row['name']):
            return crop_id
    raise ValueError(f'Unmapped cover crop product (add it to PRODUCTS): {row["id"]} {row["name"]}')


def build_varieties(rows):
    chosen = {}
    for row in sorted(rows, key=lambda r: (not r['id'].isdigit(), r['id'])):
        crop_id = map_product(row)
        if crop_id is None:
            continue
        chosen.setdefault((crop_id, row['name'].casefold()),
                          dict(id=row['id'], cropId=crop_id, name=row['name'], url=row['url']))
    return sorted(chosen.values(), key=lambda r: (r['name'].casefold(), r['id']))


def listing_links(page):
    links = set(re.findall(r'href="(https://www\.johnnyseeds\.com/cover-crops/[a-z-]+/)"', page))
    return sorted(links)


# ---------------------------------------------------------------- build

def validate(crops, varieties):
    ids = {c['id'] for c in crops}
    if len(ids) != len(crops):
        raise ValueError('Duplicate cover crop id')
    seen = set()
    for v in varieties:
        if v['cropId'] not in ids:
            raise ValueError(f'Unknown cover crop id: {v}')
        if v['id'] in seen or not v['url'].endswith('-' + v['id'] + '.html'):
            raise ValueError(f'Bad variety: {v}')
        seen.add(v['id'])


def build(chart_rows, kgi_pages, product_rows):
    unknown = sorted(set(chart_rows) - set(ROWS))
    missing = sorted(set(ROWS) - set(chart_rows))
    if unknown or missing:
        raise ValueError(f'Chart rows changed: unknown {unknown}, missing {missing}')
    crops = []
    for row_name in sorted(chart_rows, key=lambda r: ROWS[r][1].casefold()):
        crop = chart_crop(row_name, chart_rows[row_name])
        page = ROWS[row_name][2]
        crop['url'] = kgi_pages[page]['url'] if page else None
        crop['sections'] = kgi_pages[page]['sections'] if page else []
        crops.append(crop)
    varieties = build_varieties(product_rows)
    validate(crops, varieties)
    return crops, varieties


def main():
    ap = argparse.ArgumentParser(description=(__doc__ or '').split('\n\n')[0])
    ap.add_argument('--refresh', action='store_true')
    ap.add_argument('--cache', type=Path, default=DEFAULT_CACHE)
    ap.add_argument('--out', type=Path, default=DEFAULT_OUT)
    args = ap.parse_args()

    def get(url):
        return scrape.fetch(url, args.cache, args.refresh)

    chart = parse_chart(chart_words(fetch_bytes(chart_pdf_url(get(CHART_PAGE)),
                                                args.cache, args.refresh)))
    kgi_links = re.findall(r'href="(https://www\.johnnyseeds\.com/growers-library/'
                           r'farm-seed-cover-crops/[^"]*-key-growing-information\.html)"',
                           get(KGI_INDEX))
    needed = {page for _, _, page in ROWS.values() if page}
    kgi = {}
    for url in dict.fromkeys(kgi_links):
        slug = url.rsplit('/', 1)[-1].replace('-key-growing-information.html', '')
        if slug in needed:
            _, body = scrape.kgi_block(get(url))
            kgi[slug] = {'url': url, 'sections': scrape.split_sections(body)}
    if needed - set(kgi):
        raise ValueError(f'KGI pages not found: {sorted(needed - set(kgi))}')

    links = listing_links(get(LISTINGS + '?sz=1000'))
    if not links:
        raise ValueError('No cover crop listings found (blocked or changed page)')
    products = {}
    for url in links:
        for row in collect_listing(url, get):
            products[row['id']] = row
        print(f'{url}: {len(products)} products so far', flush=True)

    crops, varieties = build(chart, kgi, list(products.values()))
    left_out = sorted({r['name'] for r in products.values()
                       if '/cover-crops/' in r['url'] and map_product(r) is None})
    out = {'source': SOURCE, 'fetched': datetime.date.today().isoformat(),
           'crops': crops, 'varieties': varieties}
    scrape.publish_outputs([(args.out, json.dumps(out, indent=2, ensure_ascii=False) + '\n')])
    print(f'Wrote {len(crops)} cover crops and {len(varieties)} varieties to {args.out}')
    print('Left out (no chart row): ' + ', '.join(left_out))


if __name__ == '__main__':
    main()
