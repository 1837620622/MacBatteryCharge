import importlib.util
import pathlib
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('package_release', ROOT / 'tools/package_release.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)

class PackagingTests(unittest.TestCase):
    def test_unsigned_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = pathlib.Path(tmp)
            signed = base / 'signed'
            signed.mkdir()
            for name in package.SHORTCUTS:
                (signed / f'{name}.shortcut').write_bytes(b'<?xml fake plist>')
            with self.assertRaises(ValueError):
                package.package(ROOT, signed, base / 'out')

    def test_layout_and_mode(self):
        # Simulated AEA1 bytes for ZIP layout tests ONLY, not Apple cryptographic verification.
        with tempfile.TemporaryDirectory() as tmp:
            base = pathlib.Path(tmp)
            signed = base / 'signed'
            signed.mkdir()
            for name in package.SHORTCUTS:
                (signed / f'{name}.shortcut').write_bytes(b'AEA1' + b'X' * 256)
            result = package.package(ROOT, signed, base / 'out')
            with zipfile.ZipFile(result) as z:
                self.assertIsNone(z.testzip())
                self.assertIn('MacBatteryCharge/安装.command', z.namelist())
                self.assertIn('MacBatteryCharge/卸载.command', z.namelist())
                self.assertIn('MacBatteryCharge/SHA256SUMS.txt', z.namelist())
                self.assertIn('MacBatteryCharge/shortcuts/白天充电上限80.shortcut', z.namelist())
                self.assertEqual((z.getinfo('MacBatteryCharge/安装.command').external_attr >> 16) & 0o777, 0o755)

if __name__ == '__main__':
    unittest.main()
