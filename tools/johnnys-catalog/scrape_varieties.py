#!/usr/bin/env python3
"""Import Johnny's public product listings, independently of the KGI scraper."""
from html.parser import HTMLParser
import argparse
import datetime
import json
from pathlib import Path
import re
from urllib.parse import urljoin, urlsplit

BASE = 'https://www.johnnyseeds.com/'
HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
DEFAULT_CACHE = Path.home() / '.hermes/cache/scratch/johnnys-varieties'
SOURCE = "Johnny's Selected Seeds — public vegetable and herb product listings (https://www.johnnyseeds.com/)"


class ListingParser(HTMLParser):
    """Read only actual product tiles, never navigation or recommendations."""
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.rows = []
        self.row = None
        self.depth = 0
        self.field = None
        self.field_depth = 0

    def handle_starttag(self, tag, attrs):
        attrs = {k: v or '' for k, v in attrs}
        classes = attrs.get('class', '').split()
        if tag == 'div' and 'product' in classes and 'data-pid' in attrs:
            self.row = dict(id=attrs['data-pid'], name='', url='', secondary='', description='')
            self.depth = 0
        if self.row is None:
            return
        if tag == 'div':
            self.depth += 1
        for css, field in [('tile-name', 'name'), ('tile-secondary-name', 'secondary'),
                           ('tile-description', 'description')]:
            if css in classes:
                self.field = field
                self.field_depth = self.depth
        if tag == 'a' and 'tile-name-link' in classes:
            self.row['url'] = urljoin(BASE, attrs.get('href', ''))

    def handle_data(self, data):
        if self.row is not None and self.field:
            self.row[self.field] += data

    def handle_endtag(self, tag):
        if self.row is None or tag != 'div':
            return
        if self.depth == self.field_depth:
            self.field = None
        self.depth -= 1
        if self.depth == 0:
            self.rows.append({k: ' '.join(v.split()) for k, v in self.row.items()})
            self.row = None


def parse_listing(page):
    parser = ListingParser()
    parser.feed(page)
    return parser.rows


# Source category spellings differ from the KGI IDs. These are taxonomic
# equivalences, not per-variety assignments. Paths were observed in site nav.
CATEGORY_ALIASES = {
    'artichokes': 'artichoke', 'cucumbers': 'cucumber',
    'bush-beans': 'bush-bean', 'pole-beans': 'pole-bean',
    'fava-beans': 'fava-bean', 'lima-beans': 'lima-bean',
    'fresh-shell-beans': 'fresh-shell-bean', 'soybeans': 'soybean',
    'beet-greens': 'baby-leaf-beets',
    'belgian-endive-witloof': 'chicory-belgian-endive',
    'endive': 'chicory-endive-escarole', 'escarole': 'chicory-endive-escarole',
    'italian-dandelion': 'italian-dandelion-chicory',
    'arugula-roquette': 'arugula', 'mustard-greens': 'mustard',
    'pac-choi-bok-choy': 'pac-choi', 'greens-mixes': 'salad-mixes',
    'cipollini-onions': 'cipollini-mini-specialty-onions',
    'mini-onions': 'cipollini-mini-specialty-onions',
    'specialty-cooking-onions': 'cipollini-mini-specialty-onions',
    'daikon-korean-radishes': 'daikon-radishes',
    'parsnips': 'parsnip', 'rutabagas': 'rutabaga', 'tomatillos': 'tomatillo',
    'salsify': 'scorzonera-salsify', 'scorzonera': 'scorzonera-salsify',
    'gourds': 'ornamental-gourds', 'fennel-leaf': 'leaf-fennel',
    'sweet-corn': 'corn-sweet', 'dry-corn': 'corn-ornamental-dry-field',
}


def map_crop(row, crops):
    """Use source taxonomy and explicit crop words, not cultivar-name guesses."""
    if not row['url'].startswith(BASE) or re.search(r'\bcollection\b|\bset$', row['name'], re.I):
        return None
    path = urlsplit(row['url']).path
    parts = path.strip('/').split('/')[:-1]
    if any(word in path for word in ('rootstock', '/microgreens/', '/shoots/', '/sprouts/')):
        return None
    ids = {c['id'] for c in crops}
    text = ' '.join(row.get(k, '') for k in ('name', 'secondary', 'description')).casefold()
    specific = None
    if '/onions/' in path and 'onion sets' in row['secondary'].casefold():
        specific = 'onion-sets'
    elif '/squash/winter-squash/' in path:
        for kind in ('butternut', 'buttercup', 'kabocha', 'hubbard', 'spaghetti', 'acorn'):
            if re.search(r'\b' + kind + r'\b', row['secondary'].casefold() + ' ' + row['name'].casefold()):
                specific = kind + '-winter-squash'
                break
        if 'delicata' in row['secondary'].casefold() or 'sweet dumpling' in row['name'].casefold():
            specific = 'delicata-sweet-dumpling-winter-squash'
    elif '/squash/summer-squash/' in path:
        if 'zucchini' in row['secondary'].casefold():
            specific = 'zucchini'
        elif 'yellow summer squash' in text:
            specific = 'yellow-summer-squash'
        elif 'patty pan' in text:
            specific = 'specialty-summer-squash'
    elif '/beans/bush-beans/' in path and 'filet' in text:
        specific = 'french-filet-beans'
    elif '/broccoli/' in path and re.search(r'\b(?:raab|rabe)\b', text):
        specific = 'broccoli-raab'
    elif '/corn/' in path:
        if 'broom corn' in text:
            specific = 'broom-corn'
        elif 'super sweet' in text or 'sh2' in text:
            specific = 'corn-super-sweet'
        elif re.search(r'\bsu\b|old.fashioned', text):
            specific = 'corn-old-fashioned-sweet'
    elif '/herbs/' in path:
        herb_terms = {'roman chamomile': 'chamomile-roman', 'wild marjoram': 'wild-marjoram',
                      'greek oregano': 'oregano-greek', 'summer savory': 'summer-savory',
                      'winter savory': 'winter-savory', 'leaf fennel': 'leaf-fennel',
                      'cutting celery': 'cutting-celery'}
        for term, crop_id in herb_terms.items():
            if term in row['name'].casefold() + ' ' + row['secondary'].casefold():
                specific = crop_id
                break
        if '/herbs-for-salad-mix/' in path:
            for term in ('chervil', 'cumin', 'dandelion'):
                if re.search(r'\b' + term + r'\b', text):
                    specific = term
    elif '/greens/specialty-greens/' in path:
        for term, crop_id in [('mâche', 'mache'), ('claytonia', 'claytonia'),
                             ('malabar spinach', 'malabar-spinach'), ('orach', 'orach'),
                             ('vegetable amaranth', 'vegetable-amaranth'), ('celtuce', 'celtuce'),
                             ('purslane', 'purslane'), ('magenta spreen', 'magenta-spreen')]:
            if term in text:
                specific = crop_id
                break
    if specific:
        return specific if specific in ids else None
    # Most-specific source category wins over a broader parent category.
    for part in reversed(parts):
        if part in CATEGORY_ALIASES:
            candidate = CATEGORY_ALIASES[part]
            return candidate if candidate in ids else None
        if part in ids:
            return part
    return None


def build_varieties(rows, crops):
    """One cultivar per crop/name; prefer the unqualified numeric product ID."""
    chosen = {}
    for row in sorted(rows, key=lambda r: (not r['id'].isdigit(), r['id'], r['url'])):
        crop_id = map_crop(row, crops)
        if crop_id is None:
            continue
        name = re.sub(r'^Primed\s+|\s+Plants$|\s+[–—-]\s+(?:Early Ship|Fall-Planted|Spring-Planted)$',
                      '', row['name'], flags=re.I)
        key = (crop_id, name.casefold())
        chosen.setdefault(key, dict(id=row['id'], cropId=crop_id,
                                    name=name, url=row['url']))
    return sorted(chosen.values(), key=lambda r: (r['name'].casefold(), r['cropId'], r['id']))


def listing_links(page, crops):
    parents = {urlsplit(c['url']).path.split('/')[-2] for c in crops}
    parents.update(('salsify', 'scorzonera', 'squash', 'zucchini'))
    links = set(re.findall(r'href="(https://www\.johnnyseeds\.com/(?:vegetables|herbs)/[^/"?]+/)"', page))
    return sorted(u for u in links if u.rstrip('/').split('/')[-1] in parents)


def collect_listing(url, fetch_page):
    """Check source totals, paginate if needed, and fail closed on truncation."""
    rows = {}
    target = url + '?sz=1000'
    total = None
    while True:
        page = fetch_page(target)
        counts = re.findall(r'results-counter[^>]*>\s*([\d,]+)\s+Products?', page, re.I)
        if not counts:
            raise ValueError(f'No source product count (blocked or changed markup): {target}')
        expected = int(counts[0].replace(',', ''))
        if total is not None and expected != total:
            raise ValueError(f'Source total changed during pagination: {target}')
        total = expected
        before = len(rows)
        for row in parse_listing(page):
            if not row['id'] or not row['name'] or not row['url']:
                raise ValueError(f'Incomplete product tile: {target}')
            rows[row['id']] = row
        if len(rows) == total:
            return list(rows.values())
        if len(rows) > total or len(rows) == before:
            raise ValueError(f'Incomplete listing: {url}: {len(rows)} of {total}')
        target = url + f'?sz=1000&start={len(rows)}'


def validate(varieties, crops):
    crop_ids = {c['id'] for c in crops}
    ids, names = set(), set()
    for row in varieties:
        if set(row) != {'id', 'cropId', 'name', 'url'} or not all(isinstance(v, str) and v.strip() for v in row.values()):
            raise ValueError(f'Invalid variety schema: {row}')
        if row['cropId'] not in crop_ids:
            raise ValueError(f'Unknown crop ID: {row}')
        if row['id'] in ids or (row['cropId'], row['name'].casefold()) in names:
            raise ValueError(f'Duplicate variety: {row}')
        if not row['url'].startswith(BASE) or not urlsplit(row['url']).path.endswith('-' + row['id'] + '.html'):
            raise ValueError(f'Product ID/URL mismatch: {row}')
        ids.add(row['id'])
        names.add((row['cropId'], row['name'].casefold()))


def main():
    # Reuse only the existing polite fetcher. Always pass our cache explicitly:
    # scrape.py has a historical default pointing at another Hermes profile.
    from scrape import fetch
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh', action='store_true')
    parser.add_argument('--cache', type=Path, default=DEFAULT_CACHE)
    parser.add_argument('--crops', type=Path, default=REPO / 'flutter/assets/catalog/crops.json')
    parser.add_argument('--out', type=Path, default=REPO / 'flutter/assets/catalog/varieties.json')
    parser.add_argument('--report', type=Path, help='Audit JSON (defaults to cache/report.json)')
    args = parser.parse_args()
    crops = json.loads(args.crops.read_text(encoding='utf-8'))['crops']
    def get(url):
        return fetch(url, args.cache, args.refresh)
    nav = get(BASE + 'vegetables/?sz=2000') + get(BASE + 'herbs/?sz=2000')
    links = listing_links(nav, crops)
    if not links:
        raise ValueError('No relevant category listings found')
    rows, listings = [], []
    for url in links:
        batch = collect_listing(url, get)
        rows.extend(batch)
        listings.append(dict(url=url, products=len(batch)))
        print(f'{url}: {len(batch)} products', flush=True)
    varieties = build_varieties(rows, crops)
    validate(varieties, crops)
    if not varieties:
        raise ValueError('Refusing to replace catalog with an empty result')
    covered = {v['cropId'] for v in varieties}
    missing = sorted({c['id'] for c in crops} - covered)
    report = dict(listings=listings, sourceProducts=len({r['id'] for r in rows}),
                  varieties=len(varieties), coveredCropIds=sorted(covered), missingCropIds=missing,
                  unmappedProducts=list({r['id']: r for r in rows if map_crop(r, crops) is None}.values()),
                  products=list({r['id']: r for r in rows}.values()))
    report_path = args.report or args.cache / 'report.json'
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    output = dict(source=SOURCE, fetched=datetime.date.today().isoformat(), varieties=varieties)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.out.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(output, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    temporary.replace(args.out)
    print(f'Wrote {len(varieties)} varieties; {len(covered)}/{len(crops)} crop IDs. Validation OK.')
    print('Missing crop IDs: ' + ', '.join(missing))
    print(f'Audit report: {report_path}')


if __name__ == '__main__':
    main()
