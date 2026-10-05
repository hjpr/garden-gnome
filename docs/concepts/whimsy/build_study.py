"""Build exploratory cutouts, comparison images, and catalog coverage.

Requires Pillow. Run from any directory. Outputs stay beside this study;
no runtime assets or application files are changed. These are not approved
botanical assets: see index.html and generation-manifest.json for defects.
"""
from collections import Counter
import csv
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CROPS = [
    ('tomatoes', 'Tomato'), ('carrots', 'Carrot'),
    ('lettuce', 'Lettuce'), ('broccoli', 'Broccoli'),
    ('peppers', 'Pepper'), ('onions', 'Onion'),
    ('beets', 'Beet'), ('kale', 'Kale'),
    ('cucumber', 'Cucumber'), ('bush-bean', 'Bush bean'),
    ('corn-sweet', 'Sweet corn'), ('cabbage', 'Cabbage'),
]
STYLES = [('pocket', 'Pocket Garden'), ('field', 'Field Station'),
          ('village', 'Garden Village')]
COVERS = {'crimson-clover', 'winter-rye', 'buckwheat', 'hairy-vetch',
          'mustard-cover-crop', 'peas-and-oats-mix'}


def font(size):
    return ImageFont.truetype('DejaVuSans.ttf', size)


def cutout(image):
    """Remove near-white matte for comparison, not a production mask."""
    rgba = image.convert('RGBA')
    pixels = []
    raw = rgba.tobytes()
    for r, g, b in zip(raw[0::4], raw[1::4], raw[2::4]):
        alpha = max(0, min(255, round((250 - min(r, g, b)) * 255 / 20)))
        if alpha:
            rgb = [max(0, min(255, round((v - 255 + alpha) * 255 / alpha)))
                   for v in (r, g, b)]
            pixels.append((*rgb, alpha))
        else:
            pixels.append((0, 0, 0, 0))
    rgba.putdata(pixels)
    # A few generated leaves cross cell borders. Remove tiny disconnected
    # fragments before normalising; retain larger detached plant details.
    width, height = rgba.size
    remaining = {i for i, pixel in enumerate(pixels) if pixel[3]}
    components = []
    while remaining:
        start = remaining.pop()
        component, pending = [start], [start]
        while pending:
            i = pending.pop()
            x, y = i % width, i // width
            neighbors = []
            if x: neighbors.append(i - 1)
            if x + 1 < width: neighbors.append(i + 1)
            if y: neighbors.append(i - width)
            if y + 1 < height: neighbors.append(i + width)
            for neighbor in neighbors:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    component.append(neighbor)
                    pending.append(neighbor)
        components.append(component)
    largest = max((len(c) for c in components), default=0)
    for component in components:
        if len(component) < largest * 0.01:
            for i in component:
                pixels[i] = (0, 0, 0, 0)
    rgba.putdata(pixels)
    bounds = rgba.getbbox()
    if bounds is None:
        raise ValueError('Empty crop cell')
    return rgba.crop(bounds)


def make_samples():
    sprites = {}
    for style, title in STYLES:
        source = Image.open(HERE / 'proofs' / f'{style}-plants.png')
        rows = 3 if style == 'village' else 4
        selected = list(range(12))
        # The generated four-row sheets contain duplicates. Pick inspected
        # cells, not the erroneous purple plant or side-on corn variant.
        if style == 'pocket':
            selected[-1] = 15
        if style == 'field':
            selected[-2:] = [14, 15]
        output = HERE / 'samples' / style
        output.mkdir(parents=True, exist_ok=True)
        atlas = Image.new('RGB', (1040, 880), '#F1F2F4')
        draw = ImageDraw.Draw(atlas)
        draw.text((24, 18), title + ' / exploratory cutouts', font=font(24), fill='#1F2328')
        for index, ((crop_id, label), cell) in enumerate(zip(CROPS, selected)):
            column, row = cell % 4, cell // 4
            box = (round(column * source.width / 4), round(row * source.height / rows),
                   round((column + 1) * source.width / 4), round((row + 1) * source.height / rows))
            plant = cutout(source.crop(box))
            resample = Image.Resampling.NEAREST if style == 'field' else Image.Resampling.LANCZOS
            plant.thumbnail((224, 224), resample)
            sprite = Image.new('RGBA', (256, 256))
            sprite.alpha_composite(plant, ((256 - plant.width) // 2, (256 - plant.height) // 2))
            sprite.save(output / f'{crop_id}.png')
            sprites[(style, crop_id)] = sprite
            x, y = 8 + (index % 4) * 256, 58 + (index // 4) * 270
            display = sprite.resize((224, 224), resample)
            atlas.paste(display, (x + 16, y), display)
            draw.text((x + 18, y + 224), label, font=font(18), fill='#1F2328')
        atlas.save(HERE / 'proofs' / f'{style}-cutouts.png')
    return sprites


def make_soil_comparison(sprites):
    board = Image.new('RGB', (1440, 850), '#F1F2F4')
    draw = ImageDraw.Draw(board)
    draw.text((30, 20), 'Same soil. Same planting layout. Three art directions.', font=font(28), fill='#1F2328')
    draw.text((30, 65), 'Offline art composite, not the running Plan view. Equal sizes compare style, not real crop spacing.', font=font(17), fill='#6B7280')
    texture = Image.open(ROOT / 'flutter/assets/render/prepped_soil.jpg').convert('RGB')
    for column, (style, title) in enumerate(STYLES):
        left, top = 30 + column * 470, 150
        draw.text((left, 112), title, font=font(24), fill='#1F2328')
        bed = Image.new('RGB', (440, 495))
        for y in range(0, bed.height, texture.height):
            for x in range(0, bed.width, texture.width):
                bed.paste(texture, (x, y))
        board.paste(bed, (left, top))
        resample = Image.Resampling.NEAREST if style == 'field' else Image.Resampling.LANCZOS
        for row, crop_id in enumerate(['lettuce', 'tomatoes', 'carrots', 'kale', 'cabbage', 'corn-sweet']):
            for slot in range(5):
                sprite = sprites[(style, crop_id)].resize((64, 64), resample)
                board.paste(sprite, (left + 20 + slot * 83, top + 12 + row * 80), sprite)
        draw.text((left, 667), '32 px samples on soil', font=font(17), fill='#1F2328')
        draw.rectangle((left, 697, left + 439, 758), fill='#A0613D')
        for slot, (crop_id, _) in enumerate(CROPS):
            sprite = sprites[(style, crop_id)].resize((32, 32), resample)
            board.paste(sprite, (left + 5 + slot * 36, 711), sprite)
    draw.text((30, 798), 'Test cutouts only: botanical corrections, mask cleanup and per-crop scale calibration still required.', font=font(19), fill='#6B7280')
    board.save(HERE / 'proofs/soil-comparison.png')


def make_inventory():
    entries = []
    sample_ids = {crop_id for crop_id, _ in CROPS}
    for file in ['crops.json', 'cover_crops.json']:
        data = json.loads((ROOT / 'flutter/assets/catalog' / file).read_text())
        for crop in data['crops']:
            category = crop.get('category', 'Cover crops')
            sample = ('three style cutouts' if crop['id'] in sample_ids else
                      'cover texture study' if file == 'cover_crops.json' and crop['id'] in COVERS else '')
            entries.append(dict(catalog=file, crop_id=crop['id'], name=crop['name'],
                                category=category, concept_sample=sample,
                                production_status='not produced'))
    entries.sort(key=lambda e: (e['category'], e['name'].casefold()))
    assert len({(e['catalog'], e['crop_id']) for e in entries}) == len(entries)
    with (HERE / 'catalog-art-inventory.csv').open('w', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=list(entries[0]))
        writer.writeheader()
        writer.writerows(entries)
    return {'entries': len(entries), 'categories': dict(Counter(e['category'] for e in entries)),
            'concept_sample_entries': sum(bool(e['concept_sample']) for e in entries),
            'production_assets': 0}


def verify():
    samples = list((HERE / 'samples').glob('*/*.png'))
    assert len(samples) == len(STYLES) * len(CROPS)
    for path in samples:
        with Image.open(path) as image:
            assert image.mode == 'RGBA' and image.size == (256, 256)
            assert image.getchannel('A').getextrema() == (0, 255)
            corner = image.getpixel((0, 0))
            assert isinstance(corner, tuple) and corner[3] == 0
    for path in (HERE / 'proofs').glob('*.png'):
        with Image.open(path) as image:
            image.verify()
    return len(samples)


if __name__ == '__main__':
    make_soil_comparison(make_samples())
    inventory = make_inventory()
    print(json.dumps({'cutouts_verified': verify(), 'catalog': inventory}, indent=2))
