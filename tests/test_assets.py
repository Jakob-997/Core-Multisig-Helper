#!/usr/bin/env python3
import hashlib
from pathlib import Path
import unittest


class Assets(unittest.TestCase):
    def test_official_icon_is_unmodified(self):
        data = (Path(__file__).resolve().parents[1] / "assets/bitcoin-core.svg").read_bytes()
        blob = b"blob " + str(len(data)).encode() + b"\0" + data
        self.assertEqual(hashlib.sha1(blob).hexdigest(), "14cf0c5e115f239e535b06043966db7d5a4761cd")


if __name__ == "__main__":
    unittest.main()
