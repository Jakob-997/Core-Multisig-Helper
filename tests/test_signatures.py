#!/usr/bin/env python3
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from verify_signatures import PINNED, verify


def status(fpr):
    return f"[GNUPG:] VALIDSIG {fpr} 2026-09-22 1790000000 0 4 0 1 10 00 {fpr}\n"


class Signatures(unittest.TestCase):
    def test_two_distinct(self):
        verify("".join(map(status, PINNED)))

    def test_missing_and_duplicate(self):
        for text in ["", status(next(iter(PINNED))) * 2, status("A" * 40)]:
            with self.assertRaises(ValueError):
                verify(text)

    def test_invalid_status(self):
        for error in ["BADSIG", "EXPKEYSIG", "REVKEYSIG", "NODATA"]:
            with self.assertRaises(ValueError):
                verify("".join(map(status, PINNED)) + f"[GNUPG:] {error}\n")


if __name__ == "__main__":
    unittest.main()
