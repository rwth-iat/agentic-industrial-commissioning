from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from commissioning_core.assemble import assemble_canonical_model
from commissioning_core.matching import build_matching_result, electrical_compatibility


def signal_asset(asset_id: str, role: str, direction: str, kind: str) -> dict:
    return {
        "id": asset_id,
        "role": role,
        "ports": [{
            "id": "signal",
            "role": "signal",
            "direction": direction,
            "interface": {"kind": kind},
            "source_refs": ["src"],
        }],
    }


def model_with(assets: list[dict], connections: list[dict] | None = None) -> dict:
    return {
        "schema_version": "0.2.0",
        "system": {"id": "test"},
        "sources": [{"id": "src", "type": "other"}],
        "assets": assets,
        "physical_connections": connections or [],
    }


class CoreTests(unittest.TestCase):
    def test_assembly_preserves_declared_and_observed_provenance(self) -> None:
        first_fragment = {
            "schema_version": "0.2.0",
            "system": {"id": "test"},
            "sources": [{"id": "declared-src", "type": "other"}],
            "assets": [{"id": "device", "status": "declared", "source_refs": ["declared-src"]}],
        }
        second_fragment = {
            "schema_version": "0.2.0",
            "system": {"id": "test"},
            "sources": [{"id": "observed-src", "type": "other"}],
            "assets": [{"id": "io", "status": "observed", "source_refs": ["observed-src"]}],
        }
        model = assemble_canonical_model([first_fragment, second_fragment])
        assets = {asset["id"]: asset for asset in model["assets"]}
        self.assertEqual(assets["device"]["status"], "declared")
        self.assertEqual(assets["io"]["status"], "observed")
        self.assertEqual({source["id"] for source in model["sources"]}, {"declared-src", "observed-src"})

    def test_electrical_compatibility_rejects_kind_and_range_mismatches(self) -> None:
        current = {"direction": "output", "interface": {"kind": "analog_current", "signal_range": {"min": 4, "max": 20, "unit": {"symbol": "mA"}}}}
        voltage = {"direction": "input", "interface": {"kind": "analog_voltage", "signal_range": {"min": 0, "max": 10, "unit": {"symbol": "V"}}}}
        narrow_current = {"direction": "input", "interface": {"kind": "analog_current", "signal_range": {"min": 4, "max": 16, "unit": {"symbol": "mA"}}}}
        self.assertFalse(electrical_compatibility(current, voltage)[0])
        self.assertFalse(electrical_compatibility(current, narrow_current)[0])

    def test_unambiguous_and_incompatible_matching_scenarios(self) -> None:
        device = signal_asset("device", "sensor", "output", "analog_current")
        io = signal_asset("io", "io_module", "input", "analog_current")
        unambiguous, report = build_matching_result(model_with([device, io]))
        self.assertEqual(len(unambiguous["physical_connections"]), 1)
        self.assertEqual(report["human_questions"], [])

        io["ports"][0]["interface"]["kind"] = "analog_voltage"
        incompatible, report = build_matching_result(model_with([device, io]))
        self.assertEqual(incompatible["physical_connections"], [])
        self.assertEqual(report["human_questions"][0]["priority"], "blocking")

    def test_declared_connection_suppresses_candidates_without_becoming_validated(self) -> None:
        device = signal_asset("device", "sensor", "output", "analog_current")
        io = signal_asset("io", "io_module", "input", "analog_current")
        declared = {
            "id": "declared-connection",
            "kind": "signal",
            "endpoints": [
                {"asset_id": "device", "port_id": "signal"},
                {"asset_id": "io", "port_id": "signal"},
            ],
            "status": "declared",
        }
        result, report = build_matching_result(model_with([device, io], [declared]))
        self.assertEqual(result["physical_connections"][0]["status"], "declared")
        self.assertEqual(report["candidate_connection_ids"], [])
        self.assertEqual(report["supported_connection_ids"], ["declared-connection"])
        self.assertEqual(report["validated_connection_ids"], [])
        self.assertEqual(report["connection_checks"][0]["result"], "compatible_unvalidated")
        self.assertEqual(report["human_questions"], [])

    def test_observed_and_validated_connections_both_suppress_candidates(self) -> None:
        device = signal_asset("device", "sensor", "output", "analog_current")
        io = signal_asset("io", "io_module", "input", "analog_current")
        connection = {
            "id": "asserted-connection",
            "kind": "signal",
            "endpoints": [
                {"asset_id": "device", "port_id": "signal"},
                {"asset_id": "io", "port_id": "signal"},
            ],
            "status": "observed",
        }

        _, observed_report = build_matching_result(model_with([device, io], [connection]))
        self.assertEqual(observed_report["candidate_connection_ids"], [])
        self.assertEqual(observed_report["supported_connection_ids"], ["asserted-connection"])
        self.assertEqual(observed_report["connection_checks"][0]["result"], "compatible_unvalidated")
        self.assertEqual(observed_report["validated_connection_ids"], [])

        connection["status"] = "validated"
        _, validated_report = build_matching_result(model_with([device, io], [connection]))
        self.assertEqual(validated_report["candidate_connection_ids"], [])
        self.assertEqual(validated_report["supported_connection_ids"], ["asserted-connection"])
        self.assertEqual(validated_report["validated_connection_ids"], ["asserted-connection"])

    def test_competing_asserted_targets_are_reported_without_free_candidates(self) -> None:
        device = signal_asset("device", "sensor", "output", "analog_current")
        first_io = signal_asset("io-a", "io_module", "input", "analog_current")
        second_io = signal_asset("io-b", "io_module", "input", "analog_current")
        connections = [
            {
                "id": f"declared-{io_id}",
                "kind": "signal",
                "endpoints": [
                    {"asset_id": "device", "port_id": "signal"},
                    {"asset_id": io_id, "port_id": "signal"},
                ],
                "status": "declared",
            }
            for io_id in ("io-a", "io-b")
        ]

        _, report = build_matching_result(model_with([device, first_io, second_io], connections))

        self.assertEqual(report["candidate_connection_ids"], [])
        self.assertEqual(report["supported_connection_ids"], [])
        self.assertEqual(len(report["conflicting_field_claims"]), 1)
        self.assertIn("question-conflicting-targets-device-signal", {
            question["id"] for question in report["human_questions"]
        })

    def test_corroborating_assertions_for_same_target_are_not_duplicates(self) -> None:
        device = signal_asset("device", "sensor", "output", "analog_current")
        io = signal_asset("io", "io_module", "input", "analog_current")
        connections = [
            {
                "id": connection_id,
                "kind": "signal",
                "endpoints": [
                    {"asset_id": "device", "port_id": "signal"},
                    {"asset_id": "io", "port_id": "signal"},
                ],
                "status": status,
            }
            for connection_id, status in (("wiring-claim", "declared"), ("scan-claim", "observed"))
        ]

        _, report = build_matching_result(model_with([device, io], connections))

        self.assertEqual(report["candidate_connection_ids"], [])
        self.assertEqual(report["duplicate_channel_claims"], [])
        self.assertEqual(report["supported_connection_ids"], ["scan-claim", "wiring-claim"])

    def test_terminal_details_do_not_create_independent_signal_candidates(self) -> None:
        device = signal_asset("device", "sensor", "output", "digital")
        device["ports"].extend([
            {
                "id": "contact-plus",
                "role": "other",
                "direction": "output",
                "interface": {"kind": "digital"},
                "source_refs": ["src"],
            },
            {
                "id": "contact-minus",
                "role": "other",
                "direction": "output",
                "interface": {"kind": "digital"},
                "source_refs": ["src"],
            },
        ])
        io = signal_asset("io", "io_module", "input", "digital")

        result, report = build_matching_result(model_with([device, io]))

        self.assertEqual(len(report["candidate_connection_ids"]), 1)
        self.assertEqual(len(result["physical_connections"]), 1)

    def test_missing_asserted_endpoint_is_unverifiable_instead_of_crashing(self) -> None:
        device = signal_asset("device", "sensor", "output", "analog_current")
        declared = {
            "id": "missing-channel-declaration",
            "kind": "signal",
            "endpoints": [
                {"asset_id": "device", "port_id": "signal"},
                {"asset_id": "missing-io", "port_id": "ch1"},
            ],
            "status": "declared",
        }
        _, report = build_matching_result(model_with([device], [declared]))
        self.assertEqual(report["connection_checks"][0]["result"], "unverifiable")
        self.assertIn("missing-io", report["connection_checks"][0]["reason"])

    def test_incompatible_declared_connection_is_reported_as_conflicting(self) -> None:
        device = signal_asset("device", "sensor", "output", "analog_current")
        io = signal_asset("io", "io_module", "input", "analog_voltage")
        declared = {
            "id": "invalid-declaration",
            "kind": "signal",
            "endpoints": [
                {"asset_id": "device", "port_id": "signal"},
                {"asset_id": "io", "port_id": "signal"},
            ],
            "status": "declared",
        }
        _, report = build_matching_result(model_with([device, io], [declared]))
        self.assertEqual(report["connection_checks"][0]["result"], "conflicting")
        self.assertIn("question-reconcile-connection-invalid-declaration", {
            question["id"] for question in report["human_questions"]
        })

    def test_duplicate_io_channel_claims_are_reported(self) -> None:
        first = signal_asset("first", "sensor", "output", "digital")
        second = signal_asset("second", "sensor", "output", "digital")
        io = signal_asset("io", "io_module", "input", "digital")
        connections = [
            {
                "id": f"declared-{asset_id}",
                "kind": "signal",
                "endpoints": [
                    {"asset_id": asset_id, "port_id": "signal"},
                    {"asset_id": "io", "port_id": "signal"},
                ],
                "status": "declared",
            }
            for asset_id in ("first", "second")
        ]
        _, report = build_matching_result(model_with([first, second, io], connections))
        self.assertEqual(len(report["duplicate_channel_claims"]), 1)
        self.assertEqual(
            set(report["duplicate_channel_claims"][0]["connection_ids"]),
            {"declared-first", "declared-second"},
        )


if __name__ == "__main__":
    unittest.main()
