"""Offline tests; HTML under fixtures/ is explicitly synthetic test input."""
import importlib.util
from pathlib import Path
import sys
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))


class ListingTests(unittest.TestCase):
    def test_parses_source_id_display_name_url_and_decoded_details(self):
        self.assertIsNotNone(importlib.util.find_spec('scrape_varieties'),
                             'The variety importer must exist')
        from scrape_varieties import parse_listing
        rows = parse_listing((HERE / 'fixtures/variety-listing.html').read_text())
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0], {
            'id': '5249', 'name': 'Amalfi',
            'url': 'https://www.johnnyseeds.com/vegetables/tomatoes/paste-tomatoes/amalfi-f1-tomato-seed-5249.html',
            'secondary': '(F1) Tomato Seed', 'description': 'Early & refined.',
        })
        self.assertEqual(rows[1]['id'], '4116G')
        self.assertEqual(rows[1]['name'], 'Fixture Carrot')
        self.assertTrue(rows[1]['url'].startswith('https://www.johnnyseeds.com/'))


class ImportTests(unittest.TestCase):
    def test_discovers_only_relevant_source_listing_links(self):
        import scrape_varieties as importer
        self.assertTrue(hasattr(importer, 'listing_links'), 'Missing listing discovery')
        page = '<a href="https://www.johnnyseeds.com/vegetables/tomatoes/">Tomatoes</a>' \
               '<a href="https://www.johnnyseeds.com/vegetables/tomatoes/cherry-tomatoes/">Cherry</a>' \
               '<a href="https://www.johnnyseeds.com/vegetables/microgreens/">Microgreens</a>'
        crops = [{'id': 'tomatoes', 'url': 'https://www.johnnyseeds.com/growers-library/vegetables/tomatoes/tomatoes-key-growing-information.html'}]
        self.assertEqual(importer.listing_links(page, crops), ['https://www.johnnyseeds.com/vegetables/tomatoes/'])

    def test_follows_pagination_and_checks_declared_total(self):
        import scrape_varieties as importer
        self.assertTrue(hasattr(importer, 'collect_listing'), 'Missing pagination')
        page = (HERE / 'fixtures/variety-listing.html').read_text()
        first = page[:page.index('<div data-pid="4116G"')]
        second = '<span class="results-counter">2 Products</span>' + page[page.index('<div data-pid="4116G"'):]
        visited = []
        def fetch(url):
            visited.append(url)
            return second if 'start=1' in url else first
        self.assertEqual(len(importer.collect_listing('https://www.johnnyseeds.com/vegetables/tomatoes/', fetch)), 2)
        self.assertEqual(len(visited), 2)
        with self.assertRaises(ValueError):
            importer.collect_listing('https://www.johnnyseeds.com/vegetables/tomatoes/', lambda _: first)
        with self.assertRaises(ValueError):
            importer.collect_listing('https://www.johnnyseeds.com/vegetables/tomatoes/', lambda _: '<html>Access denied</html>')

    def test_validation_rejects_duplicate_ids_unknown_crops_and_id_url_mismatch(self):
        import scrape_varieties as importer
        self.assertTrue(hasattr(importer, 'validate'), 'Missing validation')
        row = dict(id='123', cropId='tomatoes', name='Fixture',
                   url='https://www.johnnyseeds.com/vegetables/tomatoes/fixture-123.html')
        importer.validate([row], [{'id': 'tomatoes'}])
        for rows in ([row, row], [dict(row, cropId='missing')], [dict(row, id='456')]):
            with self.assertRaises(ValueError):
                importer.validate(rows, [{'id': 'tomatoes'}])


class CollectionTests(unittest.TestCase):
    def test_normalizes_shipping_and_treatment_labels_not_strain_names(self):
        from scrape_varieties import build_varieties
        rows = [dict(id='4745ES', name='Caribou Russet – Early Ship', secondary='Seed Potatoes',
                     description='', url='https://www.johnnyseeds.com/vegetables/potatoes/fixture-4745ES.html'),
                dict(id='4745', name='Caribou Russet', secondary='Seed Potatoes',
                     description='', url='https://www.johnnyseeds.com/vegetables/potatoes/fixture-4745.html')]
        self.assertEqual(len(build_varieties(rows, [{'id': 'potatoes'}])), 1)

    def test_rejects_bundles_and_foreign_product_links(self):
        from scrape_varieties import build_varieties
        row = dict(id='123', name='Tomato Collection', secondary='Tomato Seed',
                   description='', url='https://www.johnnyseeds.com/vegetables/tomatoes/fixture-123.html')
        self.assertEqual(build_varieties([row], [{'id': 'tomatoes'}]), [])
        row.update(name='Fixture', url='https://example.com/vegetables/tomatoes/fixture-123.html')
        self.assertEqual(build_varieties([row], [{'id': 'tomatoes'}]), [])

    def test_dedupes_organic_and_treatment_forms_deterministically(self):
        import scrape_varieties as importer
        self.assertTrue(hasattr(importer, 'build_varieties'), 'Missing collection builder')
        crops = [{'id': 'tomatoes'}]
        def row(pid, secondary):
            return dict(id=pid, name='Fixture', secondary=secondary, description='',
                        url='https://www.johnnyseeds.com/vegetables/tomatoes/fixture-' + pid + '.html')
        rows = [row('123G', 'Organic Tomato Seed'), row('123', 'Tomato Seed'), row('123T', 'Treated Tomato Seed')]
        expected = [{'id': '123', 'cropId': 'tomatoes', 'name': 'Fixture', 'url': rows[1]['url']}]
        self.assertEqual(importer.build_varieties(rows, crops), expected)
        self.assertEqual(importer.build_varieties(list(reversed(rows)), crops), expected)
        self.assertEqual(importer.build_varieties(rows + rows, crops), expected)


class MappingTests(unittest.TestCase):
    def test_source_category_aliases_and_explicit_crop_descriptions(self):
        from scrape_varieties import map_crop
        cases = [
            ('vegetables/artichokes', 'Imperial Star', 'Artichoke Seed', '', 'artichoke'),
            ('vegetables/onions/onion-plants-sets', 'Shakespeare – Fall-Planted', 'Onion Sets', '', 'onion-sets'),
            ('vegetables/cucumbers/slicing-cucumbers', 'Bristol', 'Cucumber Seed', '', 'cucumber'),
            ('vegetables/beans/bush-beans', 'Tobago', 'Bean Seed', 'Attractive and refined filet bean.', 'french-filet-beans'),
            ('vegetables/beans/pole-beans', 'Fixture', 'Bean Seed', '', 'pole-bean'),
            ('vegetables/beets/beet-greens', 'Fixture', 'Beet Seed', '', 'baby-leaf-beets'),
            ('vegetables/chicory/endive', 'Fixture', 'Endive Seed', '', 'chicory-endive-escarole'),
            ('vegetables/squash/winter-squash', 'Fixture', 'Organic Kabocha Squash Seed', '', 'kabocha-winter-squash'),
            ('vegetables/squash/summer-squash', 'Fixture', 'Patty Pan Squash Seed', '', 'specialty-summer-squash'),
            ('vegetables/corn/sweet-corn', 'Fixture', 'Corn Seed', 'Organic main-season super sweet (sh2).', 'corn-super-sweet'),
            ('vegetables/corn/dry-corn', 'Mixed Broom Corn', 'Broom Corn Seed', '', 'broom-corn'),
            ('herbs/chamomile', 'Roman Chamomile', 'Herb Seed', '', 'chamomile-roman'),
            ('herbs/marjoram', 'Wild Marjoram', 'Herb Seed', '', 'wild-marjoram'),
            ('herbs/herbs-for-salad-mix', 'Bronze', 'Organic Leaf Fennel Seed', '', 'leaf-fennel'),
            ('vegetables/greens/specialty-greens', 'Vit', 'Green Seed', 'This mild-tasting mâche is the ideal winter salad item.', 'mache'),
            ('vegetables/broccoli/mini-broccoli', 'Spring Raab', 'Broccoli Seed', 'The most versatile broccoli raab.', 'broccoli-raab'),
        ]
        crops = [{'id': c[-1]} for c in cases]
        for path, name, secondary, description, expected in cases:
            with self.subTest(crop=expected):
                self.assertEqual(map_crop(dict(url='https://www.johnnyseeds.com/' + path + '/fixture-1.html',
                    name=name, secondary=secondary, description=description), crops), expected)

    def test_maps_source_taxonomy_to_existing_crop_ids_only(self):
        import scrape_varieties as importer
        self.assertTrue(hasattr(importer, 'map_crop'), 'Missing crop mapping')
        crops = [{'id': 'tomatoes', 'url': 'https://www.johnnyseeds.com/growers-library/vegetables/tomatoes/tomatoes-key-growing-information.html'},
                 {'id': 'mini-broccoli', 'url': 'https://www.johnnyseeds.com/growers-library/vegetables/broccoli/mini-broccoli-key-growing-information.html'},
                 {'id': 'broccoli', 'url': 'https://www.johnnyseeds.com/growers-library/vegetables/broccoli/broccoli-key-growing-information.html'}]
        row = {'url': 'https://www.johnnyseeds.com/vegetables/tomatoes/cherry-tomatoes/example-123.html',
               'name': 'Fixture', 'secondary': 'Tomato Seed', 'description': ''}
        self.assertEqual(importer.map_crop(row, crops), 'tomatoes')
        row['url'] = 'https://www.johnnyseeds.com/vegetables/broccoli/mini-broccoli/example-123.html'
        self.assertEqual(importer.map_crop(row, crops), 'mini-broccoli')
        row['url'] = 'https://www.johnnyseeds.com/vegetables/tomatoes/rootstock-tomatoes/example-123.html'
        self.assertIsNone(importer.map_crop(row, crops))
        row['url'] = 'https://www.johnnyseeds.com/vegetables/unknown/example-123.html'
        self.assertIsNone(importer.map_crop(row, crops))


if __name__ == '__main__':
    unittest.main()
