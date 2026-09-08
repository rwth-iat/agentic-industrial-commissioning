from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "apply-hardware-annotations.py"


def load_module():
    spec = importlib.util.spec_from_file_location("hardware_annotations", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


class HardwareAnnotationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def test_adds_reviewed_information_without_mutating_base(self):
        base = {"sources": [], "assets": [{"id": "io-a", "identification": {"source_refs": ["s"]}}], "physical_connections": []}
        annotations = {
            "sources": [{"id": "s", "type": "other"}],
            "asset_updates": [{"asset_id": "io-a", "ports": [{"id": "ch1"}]}],
            "assets": [{"id": "device-a", "identification": {"source_refs": ["s"]}}],
        }
        result = self.module.apply_annotations(base, annotations)
        self.assertNotIn("ports", base["assets"][0])
        self.assertEqual("ch1", result["assets"][0]["ports"][0]["id"])
        self.assertEqual("device-a", result["assets"][1]["id"])

    def test_rejects_silent_overwrite(self):
        base = {"sources": [], "assets": [{"id": "io-a", "name": "Original"}], "physical_connections": []}
        with self.assertRaisesRegex(ValueError, "overwrite"):
            self.module.apply_annotations(base, {"asset_updates": [{"asset_id": "io-a", "name": "Replacement"}]})


if __name__ == "__main__":
    unittest.main()
