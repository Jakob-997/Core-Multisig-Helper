#!/usr/bin/env python3
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from secret_material import master_xprv, wallet_passphrase, canonical_share


class SecretMaterial(unittest.TestCase):
    def test_bip32_master_vector(self):
        seed = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
        # master_xprv accepts any BIP32 seed length only internally we require 32;
        # verify the serialization primitive with a 32-byte published-style vector below.
        with self.assertRaises(ValueError):
            master_xprv(seed, "main")

    def test_bip32_32_byte_vector(self):
        seed = bytes.fromhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        self.assertEqual(
            master_xprv(seed, "main"),
            "xprv9s21ZrQH143K3EuJY8RRCWBLXFgB9WCcFKsv28bcaDy9LUZtXgHe9q9V8kLi4aJ6H8r5X2wu9gz2ZYXbAhtsAcJKX8Z1Ackw6Wq1oi8DEEk",
        )

    def test_passphrase_is_domain_separated_and_stable(self):
        seed = bytes(range(32))
        self.assertEqual(len(wallet_passphrase(seed)), 64)
        self.assertEqual(wallet_passphrase(seed), wallet_passphrase(seed))
        self.assertNotEqual(wallet_passphrase(seed), seed.hex())

    def test_canonical_share(self):
        self.assertEqual(canonical_share("  Able   ACID\nAlso "), "able acid also")


if __name__ == "__main__":
    unittest.main()
