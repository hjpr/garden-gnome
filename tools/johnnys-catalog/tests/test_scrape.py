"""Offline refresh safety tests using synthetic HTML and isolated scratch files."""
import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import scrape


class RefreshSafetyTests(unittest.TestCase):
    def setUp(self):
        # Explicit environment scratch root: never fall back to system temp.
        scratch = Path(os.environ['TMPDIR'])
        scratch.mkdir(parents=True, exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(prefix='johnnys-test-', dir=scratch)
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.out = self.root / 'crops.json'
        self.raw = self.root / 'raw.json'
        self.old_out = b'previous catalog\n\x00'
        self.old_raw = b'previous raw\r\n'
        self.out.write_bytes(self.old_out)
        self.raw.write_bytes(self.old_raw)
        self.overrides = self.root / 'overrides.json'
        self.overrides.write_text(json.dumps({'defaults': {
            'season': 'cool', 'frostTolerance': 'hardy', 'sowing': 'direct',
            'plantOutWeeks': [-2, 0], 'daysToMaturity': [50, 60],
            'harvestWindowDays': [7, 14], 'inRowSpacingIn': [4, 6],
            'betweenRowSpacingIn': [12, 18],
        }}), encoding='utf-8')
        self.urls = [
            'https://www.johnnyseeds.com/growers-library/vegetables/fixture-key-growing-information.html',
            'https://www.johnnyseeds.com/growers-library/herbs/herb-key-growing-information.html',
        ]
        self.pages: dict[str, str | Exception] = {
            index: f'<a href="{url}">Synthetic crop</a>'
            for (_, index), url in zip(scrape.INDEXES, self.urls)
        }
        for name, url in zip(('Fixture', 'Herb'), self.urls):
            self.pages[url] = (
                f'<div class="c-culture"><h1>{name} Key Growing Information</h1>'
                '<h2>CULTURE:</h2><p>Grow in fertile soil.</p></div>'
                '<!-- End content-asset -->'
            )

    def run_refresh(self, *extra_args):
        def response(request, **kwargs):
            body = self.pages[request.full_url]
            if isinstance(body, Exception):
                raise body
            return io.BytesIO(body.encode('utf-8'))

        self.log = io.StringIO()
        with patch.object(sys, 'argv', ['scrape.py', '--refresh', '--cache',
                str(self.root / 'cache'), '--out', str(self.out), '--raw', str(self.raw),
                *extra_args]), patch.object(scrape, 'OVERRIDES', self.overrides), \
                patch.object(scrape.urllib.request, 'urlopen', side_effect=response), \
                patch.object(scrape.time, 'sleep'), contextlib.redirect_stdout(self.log), \
                contextlib.redirect_stderr(self.log):
            try:
                scrape.main()
            except SystemExit as error:
                return error.code
        return 0

    def assert_preserved(self):
        self.assertEqual(self.out.read_bytes(), self.old_out)
        self.assertEqual(self.raw.read_bytes(), self.old_raw)

    def test_empty_or_botwall_index_preserves_outputs(self):
        for page in ('<html></html>', '<html>Access denied</html>'):
            with self.subTest(page=page):
                self.pages[scrape.INDEXES[0][1]] = page
                self.assertEqual(self.run_refresh(), 1)
                self.assert_preserved()

    def test_individual_fetch_or_parse_failure_preserves_outputs(self):
        for body in (OSError('synthetic network failure'), '<html>Access denied</html>'):
            with self.subTest(body=body):
                self.pages[self.urls[1]] = body
                self.assertEqual(self.run_refresh(), 1)
                self.assert_preserved()
                self.assertIn(self.urls[1], self.log.getvalue())

    def test_invalid_crop_is_rejected_before_either_output_changes(self):
        overrides = json.loads(self.overrides.read_text(encoding='utf-8'))
        overrides['defaults']['season'] = 'invalid-season'
        self.overrides.write_text(json.dumps(overrides), encoding='utf-8')
        self.assertEqual(self.run_refresh(), 1)
        self.assert_preserved()
        self.assertIn('bad season', self.log.getvalue())
        self.assertNotIn('Wrote', self.log.getvalue())

    def test_malformed_individual_collection_preserves_outputs(self):
        self.pages[self.urls[1]] = '<div class="c-culture"><h1>Herb</h1></div>'
        self.assertEqual(self.run_refresh(), 1)
        self.assert_preserved()

    def test_success_atomically_replaces_complete_validated_outputs(self):
        replace = os.replace
        published = []

        def inspect_replace(source, destination):
            source, destination = Path(source), Path(destination)
            self.assertEqual(source.parent, destination.parent)
            self.assertNotEqual(source, destination)
            data = json.loads(source.read_text(encoding='utf-8'))
            if destination == self.out:
                self.assertEqual(self.out.read_bytes(), self.old_out)
                self.assertEqual(scrape.validate(data['crops']), [])
                self.assertEqual(len(data['crops']), 2)
            elif destination == self.raw:
                self.assertEqual(self.raw.read_bytes(), self.old_raw)
                self.assertEqual(len(data), 2)
                self.assertTrue(all(crop['season'] is None for crop in data))
            else:
                self.fail(f'Unexpected publication: {destination}')
            published.append(destination)
            return replace(source, destination)

        with patch.object(os, 'replace', side_effect=inspect_replace):
            self.assertEqual(self.run_refresh(), 0)
        self.assertCountEqual(published, [self.out, self.raw])
        crops = json.loads(self.out.read_text(encoding='utf-8'))['crops']
        self.assertEqual([crop['id'] for crop in crops], ['fixture', 'herb'])
        self.assertEqual(len(json.loads(self.raw.read_text(encoding='utf-8'))), 2)
        self.assertEqual(set(self.root.iterdir()), {
            self.out, self.raw, self.overrides, self.root / 'cache'})

    def test_replacement_failure_restores_both_previous_files(self):
        replace = os.replace

        def fail_raw(source, destination):
            if Path(destination) == self.raw:
                raise OSError('synthetic raw replacement failure')
            return replace(source, destination)

        with patch.object(os, 'replace', side_effect=fail_raw):
            with self.assertRaises(OSError):
                self.run_refresh()
        self.assert_preserved()
        self.assertEqual(set(self.root.iterdir()), {
            self.out, self.raw, self.overrides, self.root / 'cache'})

    def test_staging_failure_preserves_both_previous_files(self):
        with patch.object(os, 'fsync', side_effect=OSError('synthetic disk failure')):
            with self.assertRaises(OSError):
                self.run_refresh()
        self.assert_preserved()
        self.assertEqual(set(self.root.iterdir()), {
            self.out, self.raw, self.overrides, self.root / 'cache'})

    def test_index_network_failure_preserves_outputs(self):
        self.pages[scrape.INDEXES[1][1]] = OSError('synthetic index failure')
        with self.assertRaises(OSError):
            self.run_refresh()
        self.assert_preserved()

    def test_default_cache_is_profile_neutral_with_environment_override(self):
        with patch.dict(os.environ):
            os.environ.pop('JOHNNYS_CACHE', None)
            defaults = runpy.run_path(scrape.__file__)
            self.assertEqual(defaults['DEFAULT_CACHE'],
                             Path.home() / '.hermes/cache/scratch/johnnys-kgi')
            os.environ['JOHNNYS_CACHE'] = str(self.root / 'env-cache')
            overridden = runpy.run_path(scrape.__file__)
            self.assertEqual(overridden['DEFAULT_CACHE'], self.root / 'env-cache')

    def test_raw_cannot_overwrite_validated_catalog(self):
        with self.assertRaises(ValueError):
            self.run_refresh('--raw', str(self.out))
        self.assert_preserved()

    def test_empty_second_index_rejects_partial_collection(self):
        self.pages[scrape.INDEXES[1][1]] = '<html>Access denied</html>'
        self.assertEqual(self.run_refresh(), 1)
        self.assert_preserved()


if __name__ == '__main__':
    unittest.main()
