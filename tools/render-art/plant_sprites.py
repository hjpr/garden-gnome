"""Turn picked overhead plant pictures into the app's plant sprites.

    python tools/render-art/plant_sprites.py \
      --picks docs/concepts/whimsy/plants/picks.json \
      --runtime flutter/assets/render/plants

Each pick is keyed off its flat background (whatever colour the corners
are; usually magenta, sometimes a dusky pink), unblended so leaf edges carry
no background tint, trimmed to the canopy and saved as a square 512 px PNG named
{kind}_{n}.png. The canopy fills the square except a thin MARGIN, so the
painter can size the canopy exactly. No shadow is baked in: the painter
turns each plant by a random angle and draws the shadow itself, so the
light stays fixed.
"""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

SIZE = 512
# Share of the square's side kept clear on each edge; the painter
# (plant_art.dart, spriteMargin) must use the same value.
MARGIN = 0.02
# Width, in source pixels (odd), of the outline band that gets despilled.
EDGE_BAND = 9


def key(image: Image.Image, near: float = 50, far: float = 130) -> Image.Image:
    """RGBA: transparent where the picture matches its corner colour."""
    rgb = np.asarray(image.convert('RGB'), dtype=np.float32)
    h, w, _ = rgb.shape
    corners = np.concatenate([rgb[:8, :8], rgb[:8, -8:], rgb[-8:, :8], rgb[-8:, -8:]])
    bg = np.median(corners.reshape(-1, 3), axis=0)
    distance = np.linalg.norm(rgb - bg, axis=2)
    alpha = np.clip((distance - near) / (far - near), 0, 1)
    # Unblend partly covered pixels from the background colour, so fine
    # leaf tips do not keep a pink rim.
    a = np.maximum(alpha, 1e-3)[..., None]
    colour = np.clip((rgb - (1 - a) * bg) / a, 0, 255)
    colour = np.where(alpha[..., None] > 0, colour, 0)
    # Despill a thin band along the outline: anti-aliased leaf edges blend
    # with the key and keep a mauve cast the unblend misses. Only the band,
    # so pink flowers inside the plant keep their colour.
    clear = Image.fromarray(((alpha < 0.5) * 255).astype(np.uint8))
    band = np.asarray(clear.filter(ImageFilter.MaxFilter(EDGE_BAND))) > 0
    excess = np.maximum(0, np.minimum(colour[..., 0], colour[..., 2]) - colour[..., 1])
    colour[..., 0] -= np.where(band, excess, 0)
    colour[..., 2] -= np.where(band, excess, 0)
    out = np.dstack([colour, alpha * 255]).astype(np.uint8)
    return Image.fromarray(out, 'RGBA')


def trim_square(rgba: Image.Image) -> Image.Image:
    """Square crop around the canopy (pixels at least half opaque)."""
    alpha = np.asarray(rgba)[..., 3]
    ys, xs = np.nonzero(alpha > 128)
    if len(xs) == 0:
        raise ValueError('nothing left after keying')
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    side = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    left, top = round(cx - side / 2), round(cy - side / 2)
    square = Image.new('RGBA', (side, side))
    square.paste(rgba.crop((left, top, left + side, top + side)), (0, 0))
    return square


def fit(canopy: Image.Image) -> Image.Image:
    """The canopy at SIZE px, inside the MARGIN."""
    inner = round(SIZE * (1 - 2 * MARGIN))
    plant = canopy.resize((inner, inner), Image.Resampling.LANCZOS)
    out = Image.new('RGBA', (SIZE, SIZE))
    pad = (SIZE - inner) // 2
    out.alpha_composite(plant, (pad, pad))
    return out


def build(picks_path: Path, runtime: Path) -> dict:
    picks = {k: v for k, v in json.loads(picks_path.read_text()).items()
             if not k.startswith('_')}
    sources = {}
    for kind, files in picks.items():
        if not 1 <= len(files) <= 3:
            raise ValueError(f'{kind}: needs 1 to 3 pictures')
        for name in files:
            path = picks_path.parent / name
            if not path.is_file():
                raise ValueError(f'{kind}: missing {name}')
        sources[kind] = [picks_path.parent / name for name in files]
    runtime.mkdir(parents=True, exist_ok=True)
    for old in runtime.glob('*.png'):
        old.unlink()
    report = {}
    for kind, paths in sources.items():
        for n, path in enumerate(paths, start=1):
            with Image.open(path) as image:
                sprite = fit(trim_square(key(image)))
            sprite.save(runtime / f'{kind}_{n}.png', optimize=True)
        report[kind] = len(paths)
    sheet_cells = [(kind, n) for kind, count in report.items() for n in range(1, count + 1)]
    cols = 8
    rows = (len(sheet_cells) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * 160, rows * 160), (120, 84, 56, 255))
    for i, (kind, n) in enumerate(sheet_cells):
        with Image.open(runtime / f'{kind}_{n}.png') as sprite:
            thumb = sprite.resize((150, 150), Image.Resampling.LANCZOS)
        sheet.alpha_composite(thumb, (i % cols * 160 + 5, i // cols * 160 + 5))
    sheet.save(picks_path.parent / 'sprites-on-soil.png')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--picks', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.picks, args.runtime), indent=2))
