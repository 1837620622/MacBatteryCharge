import importlib.util
import pathlib
import plistlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("charge_shortcuts", ROOT / "tools/charge_shortcuts.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class GeneratorTests(unittest.TestCase):
    def test_files_and_one_action(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = pathlib.Path(tmp)
            module.generate(dest)
            self.assertEqual(len(list(dest.glob("*.shortcut"))), 2)
            for name, limit, _ in module.PROFILES:
                data = (dest / f"{name}.unsigned.shortcut").read_bytes()
                module.validate(data, name, limit)
                action = plistlib.loads(data)["WFWorkflowActions"][0]
                self.assertEqual(action["WFWorkflowActionParameters"]["limit"], limit)

    def test_strict_validator(self):
        obj = module.workflow("白天充电上限80", 80)
        obj["WFWorkflowActions"][0]["WFWorkflowActionParameters"]["setUntilTomorrow"] = True
        with self.assertRaises(ValueError):
            module.validate(plistlib.dumps(obj), "白天充电上限80", 80)

    def test_deterministic_source(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            module.generate(pathlib.Path(a)); module.generate(pathlib.Path(b))
            for name, _, _ in module.PROFILES:
                file = f"{name}.unsigned.shortcut"
                self.assertEqual((pathlib.Path(a) / file).read_bytes(), (pathlib.Path(b) / file).read_bytes())

if __name__ == "__main__":
    unittest.main()
