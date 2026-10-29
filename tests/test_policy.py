import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROFILE = ROOT / "scripts" / "profile.sh"

class ProfileTests(unittest.TestCase):
    def policy(self, clock):
        proc = subprocess.run(
            ["/bin/bash", "-c", 'source "$1"; set_profile "$2"', "test", str(PROFILE), clock],
            text=True, capture_output=True
        )
        return proc.returncode, proc.stdout.strip()

    def test_boundaries(self):
        cases = {
            "0000": "100", "0100": "100", "0559": "100", "0600": "80",
            "0630": "80", "1200": "80", "2059": "80", "2100": "100",
            "2230": "100", "2330": "100", "2359": "100",
        }
        for clock, expected in cases.items():
            with self.subTest(clock=clock):
                self.assertEqual(self.policy(clock), (0, expected))

    def test_invalid(self):
        for clock in ["", "630", "2400", "1260", "2399", "abcd", "08:00", "-100", "9999"]:
            with self.subTest(clock=clock):
                rc, _ = self.policy(clock)
                self.assertEqual(rc, 2)

    def test_all_minutes_in_day(self):
        for minute in range(24 * 60):
            clock = f"{minute//60:02d}{minute%60:02d}"
            expected = "80" if 360 <= minute < 1260 else "100"
            rc, out = self.policy(clock)
            self.assertEqual((rc, out), (0, expected), clock)

if __name__ == "__main__":
    unittest.main()
