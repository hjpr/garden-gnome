"""Turn the picked ground pictures into the app's built-in texture folders.

Every picture becomes one seamless 1024 px square tile (one repeat = 5 ft
of ground) at assets/textures/<ground>/<set>-<n>.jpg, and
assets/textures/index.json lists every ground's files and its default
selection (its first set); the web build cannot list asset folders. The app builds the blended atlas from whichever tiles the user
ticks in Preferences > Textures, so no atlas is written here.

    python tools/render-art/texture_banks.py \
      --study docs/concepts/whimsy/textures \
      --picks docs/concepts/whimsy/textures/round2/picks.json \
      --runtime flutter/assets/textures

    # a texture pack (.ggtextures) of the same pictures, for testing installs
    python tools/render-art/texture_banks.py ... --pack out.ggtextures --pack-name Name

A pick is a path, or {"source": path, "scale": s}: scale > 1 crops the
middle 1/s of the picture and enlarges it back, for a picture whose shapes
came out smaller than the rest of its set (keep s at or under about 1.4).
"""

import argparse
import hashlib
import io
import json
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

MATERIALS = ('wild_grass', 'lawn', 'dirt', 'prepped_soil', 'loam', 'crimson_clover')
# Most tiles a ground can blend at once; the app enforces the same.
MAX_SELECTED = 3


def make_periodic(image: Image.Image) -> Image.Image:
    """Feather opposing edges using continuous interior detail, axis by axis.

    flutter/lib/application/texture_pixels.dart (makePeriodic) is a port;
    keep the two the same."""
    pixels = np.asarray(image.convert('RGB'), dtype=np.float32).copy()
    for axis in (0, 1):
        size = pixels.shape[axis]
        distance = np.minimum(np.arange(size), np.arange(size)[::-1])
        weight = np.clip(distance / max(1, size * 0.12), 0, 1)
        weight = weight * weight * (3 - 2 * weight)
        shape = [1, 1, 1]
        shape[axis] = size
        weight = weight.reshape(shape)
        shifted = np.roll(pixels, size // 2, axis=axis)
        pixels = pixels * weight + shifted * (1 - weight)
        first: list[int | slice] = [slice(None)] * 3
        last: list[int | slice] = [slice(None)] * 3
        first[axis], last[axis] = 0, -1
        join = (pixels[tuple(first)] + pixels[tuple(last)]) / 2
        pixels[tuple(first)] = join
        pixels[tuple(last)] = join
    return Image.fromarray(np.clip(np.rint(pixels), 0, 255).astype(np.uint8))


def match_colour(image: Image.Image, reference: Image.Image,
                 max_gain: float = 1.35) -> Image.Image:
    """Move [image]'s per-channel mean and contrast onto [reference]'s.

    Tiles that differ in brightness show up as blotches where the shader
    blends them; the contrast gain is capped so a flat picture is not
    stretched into noise. Ported to texture_pixels.dart (matchColour)."""
    src = np.asarray(image.convert('RGB'), dtype=np.float32)
    ref = np.asarray(reference.convert('RGB'), dtype=np.float32)
    mean_s, mean_r = src.mean(axis=(0, 1)), ref.mean(axis=(0, 1))
    gain = np.clip(ref.std(axis=(0, 1)) / np.maximum(src.std(axis=(0, 1)), 1e-3),
                   1 / max_gain, max_gain)
    out = (src - mean_s) * gain + mean_r
    return Image.fromarray(np.clip(np.rint(out), 0, 255).astype(np.uint8))


def rescale(image: Image.Image, scale: float, size: int) -> Image.Image:
    """[image] at [size] px with its shapes [scale] times larger (centre crop)."""
    if scale < 1:
        raise ValueError('scale below 1 would need content that is not there')
    side = round(image.width / scale)
    left = (image.width - side) // 2
    cropped = image.crop((left, left, left + side, left + side))
    return cropped.resize((size, size), Image.Resampling.LANCZOS)


def _pick(entry) -> tuple[str, float]:
    if isinstance(entry, str):
        return entry, 1.0
    return entry['source'], float(entry.get('scale', 1.0))


def _load(study: Path, picks_path: Path, tile_size: int):
    """Every set's pictures, checked before anything is written."""
    picks = {k: v for k, v in json.loads(picks_path.read_text()).items()
             if not k.startswith('_')}
    if set(picks) != set(MATERIALS):
        raise ValueError(f'Picks must name exactly {sorted(MATERIALS)}')
    hashes: dict[str, str] = {}
    sets: dict[str, list[tuple[str, list[tuple[Image.Image, float]]]]] = {}
    for material in MATERIALS:
        groups = picks[material]
        if not groups:
            raise ValueError(f'{material}: needs at least one set')
        if not 1 <= len(groups[0]['sources']) <= MAX_SELECTED:
            raise ValueError(f'{material}: the default set needs 1 to {MAX_SELECTED} pictures')
        sets[material] = []
        names = set()
        for group in groups:
            name = group['name']
            if not name.replace('_', '').isalnum() or name in names:
                raise ValueError(f'{material}: bad or repeated set name {name!r}')
            names.add(name)
            pictures = []
            for entry in group['sources']:
                source, scale = _pick(entry)
                path = study / source
                if not path.is_file():
                    raise ValueError(f'{material}: missing {source}')
                with Image.open(path) as image:
                    image = image.convert('RGB')
                if image.width != image.height or image.width < tile_size:
                    raise ValueError(f'{source}: must be square and at least {tile_size}px')
                if not 1 <= scale <= 2:
                    raise ValueError(f'{source}: scale must be between 1 and 2')
                digest = hashlib.sha256(image.tobytes()).hexdigest()
                if digest in hashes:
                    raise ValueError(f'{source}: same pixels as {hashes[digest]}')
                hashes[digest] = source
                pictures.append((image, scale))
            sets[material].append((name, pictures))
    return sets


def _tiles(pictures, tile_size):
    sized = [rescale(image, scale, tile_size) for image, scale in pictures]
    return [make_periodic(image if i == 0 else match_colour(image, sized[0]))
            for i, image in enumerate(sized)]


def build_library(study: Path, picks_path: Path, runtime: Path,
                  tile_size: int = 1024) -> dict:
    sets = _load(study, picks_path, tile_size)
    runtime.mkdir(parents=True, exist_ok=True)
    review = picks_path.parent / 'processed'
    review.mkdir(parents=True, exist_ok=True)
    catalog: dict[str, dict[str, list[str]]] = {}
    report: dict[str, list[str]] = {}
    for material in MATERIALS:
        folder = runtime / material
        folder.mkdir(exist_ok=True)
        for old in folder.glob('*.jpg'):
            old.unlink()
        files = []
        for index, (name, pictures) in enumerate(sets[material]):
            tiles = _tiles(pictures, tile_size)
            names = [f'{name}-{n}.jpg' for n in range(1, len(tiles) + 1)]
            for tile, file in zip(tiles, names):
                tile.save(folder / file, quality=92, subsampling=0)
            if index == 0:
                index_entry = names
                _review_sheet(tiles, review / f'{material}-repeats.jpg', tile_size)
            files += names
        report[material] = files
        catalog[material] = {'files': files, 'default': index_entry}
    (runtime / 'index.json').write_text(json.dumps(catalog, indent=2) + '\n')
    return report


def build_pack(study: Path, picks_path: Path, out: Path, name: str,
               tile_size: int = 1024) -> None:
    """A .ggtextures pack holding every picked picture, for install tests."""
    sets = _load(study, picks_path, tile_size)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as pack:
        pack.writestr('pack.json', json.dumps({'name': name, 'author': 'Garden Gnome'}))
        for material in MATERIALS:
            for set_name, pictures in sets[material]:
                for n, tile in enumerate(_tiles(pictures, tile_size), start=1):
                    data = io.BytesIO()
                    tile.save(data, 'JPEG', quality=90)
                    pack.writestr(f'textures/{material}/{set_name}-{n}.jpg', data.getvalue())


def _review_sheet(tiles, path, tile_size):
    """Each tile as a 2 x 2 repeat at half size, to look for seams."""
    half = tile_size // 2
    sheet = Image.new('RGB', (half * 2 * len(tiles), half * 2))
    for index, tile in enumerate(tiles):
        thumb = tile.resize((half, half), Image.Resampling.LANCZOS)
        for x in range(2):
            for y in range(2):
                sheet.paste(thumb, (index * half * 2 + x * half, y * half))
    sheet.save(path, quality=90)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--study', type=Path, required=True)
    parser.add_argument('--picks', type=Path, required=True)
    parser.add_argument('--runtime', type=Path)
    parser.add_argument('--pack', type=Path)
    parser.add_argument('--pack-name', default='Texture pack')
    parser.add_argument('--tile-size', type=int, default=1024)
    args = parser.parse_args()
    if args.runtime:
        print(json.dumps(build_library(args.study, args.picks, args.runtime,
                                       args.tile_size), indent=2))
    if args.pack:
        build_pack(args.study, args.picks, args.pack, args.pack_name, args.tile_size)
