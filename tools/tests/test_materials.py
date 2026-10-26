import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class MaterialsTest(unittest.TestCase):
    def model(self):
        filename = ROOT / "forge/materials.py"
        self.assertTrue(filename.exists(), "native material model must exist")
        spec = importlib.util.spec_from_file_location("native_materials", filename)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_native_material_bounds_and_unsupported_mapping(self):
        model = self.model()
        state = {"schema": "brahma.material-state.v1", "modelVersion": 1, "phase": "gas", "amount": 1,
                 "composition": [{"id": "water", "fraction": 1}]}
        result = model.resolve("agent_smith_identity", {"replicationCount": 8}, state)
        self.assertLessEqual(result["params"]["replicationCount"], 8)
        with self.assertRaisesRegex(ValueError, "mapping|unsupported"):
            model.resolve("missing", {}, state)
        with self.assertRaisesRegex(ValueError, "amount"):
            model.validate({**state, "amount": True})

    def test_native_catalogue_keeps_every_definition_and_declares_material_support(self):
        import json
        import subprocess
        catalog = json.loads(subprocess.check_output(["python3", str(ROOT / "forge/assimilate.py"), "--catalogue"], cwd=ROOT))
        self.assertGreater(len(catalog), 200)
        by_name = {item["name"]: item for item in catalog}
        self.assertIn("material", by_name["ditto_morphic_core"])
        self.assertTrue(by_name["ditto_morphic_core"]["material"]["supported"])
        infrastructure = next(item for item in catalog if item["role"] == "infrastructure")
        self.assertFalse(infrastructure["material"]["supported"])
