from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
EXTRACTOR = ROOT / "generated" / "connectors" / "twincat-static-project" / "extract.py"
FIXTURE = ROOT / "tests" / "fixtures" / "twincat-static-project"
VARIANT = ROOT / "tests" / "fixtures" / "twincat-static-project-variant"
FRESHNESS = ROOT / "scripts" / "check-reconstruction-freshness.py"


def load_extractor():
    spec = importlib.util.spec_from_file_location("twincat_static_extract", EXTRACTOR)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


class StaticProjectExtractorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.extractor = load_extractor()
        spec = importlib.util.spec_from_file_location("freshness", FRESHNESS)
        cls.freshness = importlib.util.module_from_spec(spec)
        assert spec.loader
        spec.loader.exec_module(cls.freshness)

    def test_extracts_source_driven_inventory_and_inactive_code(self):
        facts = self.extractor.extract(FIXTURE)
        variable_names = {item["name"] for item in facts["variables"]}
        self.assertIn("PumpAlpha", variable_names)
        self.assertIn("ValveCommand", variable_names)
        self.assertEqual(1, len(facts["io_links"]))
        self.assertEqual(2, len(facts["hardware_nodes"]))
        self.assertEqual(facts["hardware_nodes"][0]["id"], facts["hardware_nodes"][1]["parent_ref"])
        self.assertTrue(any("DeprecatedValve" in item["text"] for item in facts["inactive_fragments"]))
        self.assertFalse(any("DeprecatedValve" in item["target"] for item in facts["assignments"]))

    def test_rename_and_addition_change_facts_without_tool_table(self):
        before = self.extractor.extract(FIXTURE)
        after = self.extractor.extract(VARIANT)
        names = {item["name"] for item in after["variables"]}
        self.assertNotIn("PumpAlpha", names)
        self.assertIn("MixerRenamed", names)
        self.assertIn("NewlyAddedSensor", names)
        self.assertNotEqual(before["source_revision"], after["source_revision"])

    def test_mapping_change_is_detected_and_invalidates_derivation(self):
        before = self.extractor.extract(FIXTURE)
        after = self.extractor.extract(VARIANT)
        self.assertNotEqual(before["io_links"], after["io_links"])
        self.assertNotEqual(before["facts_revision"], after["facts_revision"])
        stale_manifest = {"software_facts_revision": before["facts_revision"]}
        self.assertFalse(self.freshness.is_current(after, stale_manifest))


if __name__ == "__main__":
    unittest.main()
