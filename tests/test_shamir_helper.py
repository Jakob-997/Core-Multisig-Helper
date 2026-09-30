#!/usr/bin/env python3
import os
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from secret_material import POLICIES, recover_secret, split_secret, validate_share, verify_every_combination


@unittest.skipUnless(os.environ.get("GLACIER_SHAMIR_HELPER"), "helper not built")
class ShamirHelper(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = Path(os.environ["GLACIER_SHAMIR_HELPER"])

    def test_all_policies_and_all_combinations(self):
        secret = bytes(range(32))
        for threshold, count in POLICIES:
            shares = split_secret(self.helper, secret, threshold, count)
            self.assertEqual(verify_every_combination(self.helper, shares, secret),
                             __import__("math").comb(count, threshold))
            self.assertEqual(recover_secret(self.helper, shares[:threshold]), secret)

    def test_corruption_rejected(self):
        share = split_secret(self.helper, bytes(range(32)), 2, 3)[0]
        words = share.split()
        words[-1] = "able" if words[-1] != "able" else "acid"
        with self.assertRaises(RuntimeError):
            validate_share(self.helper, " ".join(words))

    def test_trailing_garbage_rejected(self):
        share = split_secret(self.helper, bytes(range(32)), 2, 3)[0]
        with self.assertRaises(RuntimeError):
            validate_share(self.helper, share + " abc")

    def test_mixed_sets_rejected(self):
        a = split_secret(self.helper, bytes(range(32)), 2, 3)
        b = split_secret(self.helper, bytes(reversed(range(32))), 2, 3)
        with self.assertRaises(RuntimeError):
            recover_secret(self.helper, [a[0], b[1]])


if __name__ == "__main__":
    unittest.main()
