"""Offline tests for the winter planting chart parser (synthetic HTML)."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import winter_charts


def chart(rows, weeks=(9, 8, 7, 6, 5)):
    """A chart table shaped like Johnny's: an image header row, then rows
    whose first row per tier has an extra leading tier cell."""
    alts = ["CROP", "Start Transplant", "Direct Seed",
            *[f"Week {w}" for w in weeks], "10-hour day", "Tier 1"]
    head = "<tr>" + "".join(f'<th><img alt="{a}"/></th>' for a in alts) + "</tr>"
    body = ""
    for lead, name, t, d, sown in rows:
        cells = [name, "✔" if t else "", "✔" if d else "",
                 *[str(w) if w in sown else "" for w in weeks], ""]
        if lead:
            cells = [f'<img alt="{lead}"/>'] + cells
        body += "<tr>" + "".join(f"<td>{c}</td>" for c in cells) + "</tr>"
    return f"<html><table>{head}{body}</table></html>"


class ParseTests(unittest.TestCase):
    def test_rows_methods_weeks_and_tiers(self):
        rows = winter_charts.parse_chart(chart([
            ("Tier 1", "Kale (Full)", True, False, {9, 8}),
            (None, "Spinach (Baby)", False, True, {6, 5}),
            ("Tier 2", "Broccoli Raab*", True, True, {9, 8, 6, 5}),
        ]))
        self.assertEqual([r["name"] for r in rows],
                         ["Kale (Full)", "Spinach (Baby)", "Broccoli Raab"])
        self.assertEqual(rows[0]["weeks"], [9, 8])
        self.assertEqual([r["tier"] for r in rows], [1, 1, 2])
        self.assertTrue(rows[1]["direct"] and not rows[1]["transplant"])

    def test_split_runs_give_transplant_the_earlier_weeks(self):
        row = {"name": "Broccoli Raab", "transplant": True, "direct": True,
               "weeks": [9, 8, 6, 5], "tier": 2}
        out = winter_charts.windows_for("winterHarvest", "highTunnel", row)
        self.assertEqual([(w["method"], w["weeksBefore"]) for w in out],
                         [("transplant", [8, 9]), ("direct", [5, 6])])

    def test_one_run_is_shared_by_both_methods(self):
        row = {"name": "Spinach (Full)", "transplant": True, "direct": True,
               "weeks": [8, 7], "tier": 1}
        out = winter_charts.windows_for("winterHarvest", "highTunnel", row)
        self.assertEqual([w["weeksBefore"] for w in out], [[7, 8], [7, 8]])

    def test_a_changed_page_is_refused(self):
        with self.assertRaises(ValueError):
            winter_charts.parse_chart("<html>no table</html>")
        with self.assertRaises(ValueError):
            winter_charts.parse_chart(chart([]))

    def test_attach_maps_rows_and_refuses_unknown_ones(self):
        crops = [{"id": "kale"}, {"id": "spinach"}]
        rows = [{"name": "Kale (Baby)", "transplant": False, "direct": True,
                 "weeks": [7, 6], "tier": 1}]
        winter_charts.attach(crops, [("overwinter", "lowTunnel", rows)])
        self.assertEqual(crops[0]["winterWindows"], [{
            "use": "overwinter", "structure": "lowTunnel", "method": "direct",
            "weeksBefore": [6, 7], "tier": 1, "detail": "baby leaf",
        }])
        self.assertEqual(crops[1]["winterWindows"], [])
        with self.assertRaises(ValueError):
            winter_charts.attach(crops, [("overwinter", "lowTunnel", [
                {**rows[0], "name": "Okra (Winter)"}])])


if __name__ == "__main__":
    unittest.main()
