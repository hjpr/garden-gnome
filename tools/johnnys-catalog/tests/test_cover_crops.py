"""Offline tests for cover_crops.py; the chart words below are synthetic."""
from pathlib import Path
import sys
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import cover_crops  # noqa: E402


def word(x, y, text):
    return f'<word xMin="{x}" yMin="{y}" xMax="{x + 10}" yMax="{y + 9}">{text}</word>'


# A two-row chart laid out like Johnny's: data headers on one line, rotated
# benefit headers above them to the right, the footnote key underneath.
HEADER_Y = 179
WORDS = [
    word(117, HEADER_Y, 'Sowing'), word(208, HEADER_Y, 'Minimum'),
    word(258, HEADER_Y, 'Hardiness'), word(298, HEADER_Y, 'Growth'),
    word(334, HEADER_Y, 'Sow'), word(379, HEADER_Y, 'Sow'),
    word(429, HEADER_Y, 'Seeding'), word(429, 187, 'Depth'), word(258, 187, 'Zone'),
    word(465, 169, 'Nitrogen'), word(480, 148, 'Bees/Beneficial'),
    word(494, 159, 'Compaction'), word(509, 172, 'Erosion'),
    word(524, 178, 'Weed'), word(539, 177, 'Green'), word(554, 174, 'Forage'),
    word(569, 170, 'Biomass'),
    # Row 1: a name that contains a header word ("Green").
    word(31, 330, 'Manure'), word(60, 330, 'Mix,'), word(80, 330, 'Fall'),
    word(95, 330, 'Green'),
    word(117, 330, 'Summer'), word(150, 330, 'to'), word(160, 330, 'Fall'),
    word(208, 330, '45°F'), word(223, 330, '(7°C)'), word(258, 330, 'Various'),
    word(298, 330, 'Medium'), word(334, 330, '1½'), word(345, 330, 'Lb.'),
    word(379, 330, '50'), word(390, 330, 'Lb.'), word(429, 330, '½–1½&quot;'),
    word(465, 327, '•'), word(539, 327, '•'),
    # Row 2: a NEW badge a little above the line, a frost-seeding mark, 2Y.
    word(32, 536.6, 'NEW'), word(46, 536.1, 'Clover,'), word(70, 536.1, 'Sweet'),
    word(117, 536.1, 'Spring'), word(140, 536.1, '†'),
    word(208, 536.1, '42°F'), word(258, 536.1, '4'), word(298, 536.1, 'Slow'),
    word(334, 536.1, '¼–½'), word(345, 536.1, 'Lb.'), word(379, 536.1, '8–12'),
    word(390, 536.1, 'Lb.'), word(429, 536.1, '¼–1&quot;'),
    word(480, 535, '2Y'), word(569, 533, '•'),
    word(31, 560, '†'), word(40, 560, '='),
]
BBOX = '\n'.join(WORDS)


class ChartTests(unittest.TestCase):
    def test_reads_rows_columns_and_benefits(self):
        rows = cover_crops.parse_chart(cover_crops.parse_bbox(BBOX))
        self.assertEqual(list(rows), ['Manure Mix, Fall Green', 'Clover, Sweet'])
        fall = rows['Manure Mix, Fall Green']
        self.assertEqual(fall['sowingSeason'], 'Summer to Fall')
        self.assertEqual(fall['hardinessZone'], 'Various')
        self.assertEqual(fall['seedPer1000SqFt'], '1½ Lb.')
        self.assertEqual(fall['seedPerAcre'], '50 Lb.')
        self.assertEqual(fall['sowingDepth'], '½–1½"')
        self.assertEqual([b['name'] for b in fall['benefits']],
                         ['Nitrogen fixation', 'Green manure'])
        clover = cover_crops.chart_crop('Clover, Sweet', rows['Clover, Sweet'])
        self.assertTrue(clover['frostSeeding'])
        self.assertEqual(clover['sowingSeason'], 'Spring')
        self.assertEqual(clover['minGermTempF'], 42)
        self.assertEqual(clover['benefits'], [
            {'name': 'Bees and beneficial insects', 'secondYear': True},
            {'name': 'Biomass', 'secondYear': False},
        ])

    def test_unknown_or_missing_rows_fail(self):
        rows = cover_crops.parse_chart(cover_crops.parse_bbox(BBOX))
        with self.assertRaisesRegex(ValueError, 'Chart rows changed'):
            cover_crops.build(rows, {}, [])


class ProductTests(unittest.TestCase):
    def tile(self, pid, name, path='cover-crops/legumes/'):
        return dict(id=pid, name=name, url=f'https://www.johnnyseeds.com/{path}x-{pid}.html',
                    secondary='', description='')

    def test_maps_products_and_leaves_out_tools_and_rows_without_a_chart_row(self):
        varieties = cover_crops.build_varieties([
            self.tile('982G', 'Crimson Clover'), self.tile('982', 'Crimson Clover'),
            self.tile('5901', 'Berseem Clover'),
            self.tile('6204', 'Cover Crop Termination Bar', 'tools-supplies/'),
        ])
        self.assertEqual(varieties, [dict(
            id='982', cropId='crimson-clover', name='Crimson Clover',
            url='https://www.johnnyseeds.com/cover-crops/legumes/x-982.html')])

    def test_an_unknown_product_fails(self):
        with self.assertRaisesRegex(ValueError, 'Unmapped'):
            cover_crops.build_varieties([self.tile('1', 'Mystery Bean')])


if __name__ == '__main__':
    unittest.main()
