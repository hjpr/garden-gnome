"""Unit tests use synthetic images, never substitute them for generated art."""
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

import numpy as np
from PIL import Image

import texture_banks as banks


def _picks(root: Path, size: int = 64) -> Path:
    """Two sets per ground (3 + 1 distinct synthetic pictures) and a picks file."""
    (root / 'study/raw').mkdir(parents=True)
    picks = {}
    for m, material in enumerate(banks.MATERIALS):
        sets = []
        for s, (set_name, count) in enumerate([('soft', 3), ('extra', 1)]):
            names = []
            for v in range(count):
                name = f'raw/{material}-{set_name}-{v}.png'
                rng = np.random.default_rng(m * 100 + s * 10 + v)
                Image.fromarray(rng.integers(0, 255, (size, size, 3), dtype=np.uint8)).save(
                    root / 'study' / name)
                names.append(name)
            sets.append({'name': set_name, 'sources': names})
        picks[material] = sets
    path = root / 'study/round/picks.json'
    path.parent.mkdir(parents=True)
    path.write_text(json.dumps(picks))
    return path


class TextureBanksTest(unittest.TestCase):
    def test_conditioning_removes_wrap_jump_without_changing_the_center(self):
        pixels = np.zeros((64, 64, 3), dtype=np.uint8)
        pixels[:, :32] = [60, 100, 30]
        pixels[:, 32:] = [150, 180, 90]
        pixels[22:42, 22:42] = [210, 50, 20]
        original = Image.fromarray(pixels)
        processed = np.asarray(banks.make_periodic(original))
        np.testing.assert_array_equal(processed[:, 0], processed[:, -1])
        np.testing.assert_array_equal(processed[0], processed[-1])
        np.testing.assert_array_equal(processed[22:42, 22:42], pixels[22:42, 22:42])
        np.testing.assert_array_equal(np.asarray(original), pixels)

    def test_colour_match_moves_mean_and_caps_contrast_gain(self):
        rng = np.random.default_rng(1)
        ref = Image.fromarray(rng.integers(100, 200, (32, 32, 3), dtype=np.uint8))
        flat = Image.fromarray(np.full((32, 32, 3), 40, dtype=np.uint8))
        flat.putpixel((0, 0), (41, 41, 41))
        out = np.asarray(banks.match_colour(flat, ref), dtype=np.float32)
        np.testing.assert_allclose(out.mean(axis=(0, 1)),
                                   np.asarray(ref, dtype=np.float32).mean(axis=(0, 1)),
                                   atol=1.0)
        # A nearly flat picture is not stretched into noise.
        self.assertLess(out.std(), 2)

    def test_rescale_enlarges_the_centre_and_refuses_shrinking(self):
        pixels = np.zeros((40, 40, 3), dtype=np.uint8)
        pixels[10:30, 10:30] = 255
        out = np.asarray(banks.rescale(Image.fromarray(pixels), 2, 40))
        self.assertEqual(out.shape, (40, 40, 3))
        self.assertTrue((out[5:35, 5:35] > 200).all())
        with self.assertRaises(ValueError):
            banks.rescale(Image.fromarray(pixels), 0.5, 40)

    def test_build_checks_every_pick_before_writing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            picks = _picks(root)
            runtime = root / 'runtime'
            data = json.loads(picks.read_text())
            data['loam'][0]['sources'] *= 2  # six pictures in the default set
            picks.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, 'loam'):
                banks.build_library(root / 'study', picks, runtime, tile_size=32)
            self.assertFalse(runtime.exists())
            data = json.loads(_picks_reset(picks))
            data['loam'][1]['sources'] = [data['dirt'][0]['sources'][0]]
            picks.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, 'same pixels'):
                banks.build_library(root / 'study', picks, runtime, tile_size=32)
            self.assertFalse(runtime.exists())

    def test_build_writes_a_folder_per_ground_and_an_index(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            picks = _picks(root)
            data = json.loads(picks.read_text())
            data['lawn'][0]['sources'][1] = {'source': data['lawn'][0]['sources'][1],
                                             'scale': 1.2}
            picks.write_text(json.dumps(data))
            runtime = root / 'runtime'
            banks.build_library(root / 'study', picks, runtime, tile_size=32)
            index = json.loads((runtime / 'index.json').read_text())
            for material in banks.MATERIALS:
                self.assertEqual(index[material]['files'],
                                 ['soft-1.jpg', 'soft-2.jpg', 'soft-3.jpg', 'extra-1.jpg'])
                self.assertEqual(index[material]['default'],
                                 ['soft-1.jpg', 'soft-2.jpg', 'soft-3.jpg'])
                for name in index[material]['files']:
                    with Image.open(runtime / material / name) as image:
                        self.assertEqual(image.size, (32, 32))

    def test_pack_has_pack_json_and_ground_folders(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            picks = _picks(root)
            out = root / 'test.ggtextures'
            banks.build_pack(root / 'study', picks, out, 'Test', tile_size=32)
            with zipfile.ZipFile(out) as pack:
                names = pack.namelist()
                self.assertEqual(json.loads(pack.read('pack.json'))['name'], 'Test')
            self.assertIn('textures/loam/soft-1.jpg', names)
            self.assertIn('textures/crimson_clover/extra-1.jpg', names)


def _picks_reset(picks: Path) -> str:
    """The picks file as _picks wrote it (sets with original sources)."""
    data = json.loads(picks.read_text())
    data['loam'][0]['sources'] = data['loam'][0]['sources'][:3]
    return json.dumps(data)


if __name__ == '__main__':
    unittest.main()
