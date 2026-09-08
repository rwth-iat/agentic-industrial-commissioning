import copy
import json
import unittest
from pathlib import Path

from commissioning_core.component_knowledge import generate_runtime_candidates, query_component


ROOT = Path(__file__).resolve().parents[2]


def load(relative_path):
    return json.loads((ROOT / relative_path).read_text(encoding="utf-8"))


class ComponentKnowledgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.hardware = load("examples/hardware-models/process-cell.synthetic.v0.2.json")
        cls.software = load("examples/software-models/process-cell.synthetic.v0.1.json")
        cls.links = load("examples/implementation-links/process-cell.synthetic.v0.1.json")

    def query_valve(self, **kwargs):
        return query_component(self.hardware, self.software, self.links, "control-valve", **kwargs)

    def test_reuses_partial_component_knowledge_with_conditions_and_gaps(self):
        result = self.query_valve()
        self.assertEqual("partial", result["knowledge_state"])
        self.assertEqual("reuse", result["reuse_decision"])
        self.assertTrue(result["component_interfaces"][0]["dependencies"])
        self.assertTrue(result["implementation_links"])
        self.assertTrue(result["gaps"])
        self.assertFalse(result["safety"]["executable_authorization"])

    def test_missing_component_returns_facts_for_targeted_reconstruction(self):
        facts = {"variables": [{"name": "Area03NewPump17", "datatype": "BOOL"}]}
        result = query_component(self.hardware, self.software, self.links, "NewPump17", facts=facts)
        self.assertEqual("missing", result["knowledge_state"])
        self.assertEqual("targeted_reconstruction", result["reuse_decision"])
        self.assertEqual(facts["variables"], result["reconstruction_scope"]["matching_facts"]["variables"])

    def test_stale_evidence_prevents_reuse(self):
        issue = {"kind": "revision_mismatch", "locator": "source"}
        result = self.query_valve(freshness_issues=[issue])
        self.assertEqual("stale", result["knowledge_state"])
        self.assertEqual("targeted_reconstruction", result["reuse_decision"])

    def test_static_runtime_disagreement_is_preserved(self):
        runtime = {"bindings": [{
            "id": "runtime-valve-command", "asset_id": "demo-control-valve",
            "role": "manual_setpoint", "datatype": "BOOL",
            "extensions": {"software.signal_id": "valve-command"},
        }]}
        result = self.query_valve(runtime_documents=[runtime])
        self.assertEqual("conflicting", result["knowledge_state"])
        self.assertEqual("datatype", result["runtime_disagreements"][0]["field"])
        self.assertEqual("not_established_by_static_model", result["runtime_checks"][0]["access_assessment"])

    def test_rejected_links_are_not_reused(self):
        links = copy.deepcopy(self.links)
        for link in links["links"]:
            if link["hardware"].get("component_asset_id") == "demo-control-valve":
                link["status"] = "rejected"
        result = query_component(self.hardware, self.software, links, "control-valve")
        self.assertEqual("rejected", result["knowledge_state"])
        self.assertEqual("targeted_reconstruction", result["reuse_decision"])

    def test_runtime_candidates_are_private_inferred_and_read_only(self):
        document = generate_runtime_candidates(
            self.software, {"demo-control-valve"}, environment_id="synthetic-offline",
            platform="synthetic", connection_profile="synthetic-profile",
            model_ref="examples/software-models/process-cell.synthetic.v0.1.json",
        )
        self.assertEqual("private", document["data_classification"])
        self.assertTrue(document["bindings"])
        self.assertTrue(all(item["status"] == "inferred" for item in document["bindings"]))
        self.assertTrue(all(item["access"] == "read" for item in document["bindings"]))
        self.assertFalse(document["extensions"]["safety.executable_authorization"])


if __name__ == "__main__":
    unittest.main()
