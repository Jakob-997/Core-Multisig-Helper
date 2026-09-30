#!/usr/bin/env python3
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from desktop_identity import generate, apply
from PIL import Image


class Identity(unittest.TestCase):
    def test_generate_once(self):
        with tempfile.TemporaryDirectory() as folder:
            result = generate(folder, "main")
            self.assertRegex(result["code"], r"^[0-9A-F]{4}(-[0-9A-F]{4}){4}$")
            self.assertEqual(result["network"], "main")
            image = Image.open(Path(folder) / "wallpaper.png")
            self.assertEqual(image.size, (1920, 1080))
            self.assertEqual("#" + "".join(f"{x:02X}" for x in image.getpixel((0, 0))), result["color"])
            before = (Path(folder) / "identity.json").read_bytes()
            with self.assertRaises(RuntimeError):
                generate(folder, "main")
            self.assertEqual((Path(folder) / "identity.json").read_bytes(), before)
            self.assertEqual(json.loads(before), result)

    def test_apply_isolated_preferences_and_watch_copy(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder) / "home"
            home.mkdir()
            (home / "Desktop").mkdir()
            identity = Path(folder) / "identity"
            identity.mkdir()
            generate(identity, "main")
            (identity / "watch-only.dat").write_bytes(b"public-wallet-test-fixture")
            values = {}
            def settings(action, *args):
                if action == "list-schemas":
                    return "org.gnome.desktop.background\norg.gnome.desktop.screensaver\norg.gnome.shell"
                if action == "list-keys":
                    return "picture-uri\npicture-uri-dark\npicture-options"
                schema, key = args[:2]
                if action == "get":
                    return values.get((schema, key), "[]" if key == "favorite-apps" else "'old'")
                if action == "set":
                    values[(schema, key)] = args[2]
                    return ""
                raise AssertionError(action)
            with patch("desktop_identity.os.geteuid", return_value=1000), patch("desktop_identity.Path.home", return_value=home), \
                 patch("desktop_identity.gs", side_effect=settings), \
                 patch("desktop_identity.subprocess.check_output", return_value=str(home / "Desktop")), \
                 patch("desktop_identity.subprocess.run") as run:
                run.return_value.returncode = 0
                apply(identity, "main")
            self.assertEqual((home / ".local/share/glacier2/core/wallets/watch_only/wallet.dat").read_bytes(), b"public-wallet-test-fixture")
            self.assertIn("glacier2-bitcoin.desktop", values[("org.gnome.shell", "favorite-apps")])
            self.assertEqual(values[("org.gnome.desktop.background", "picture-uri")], values[("org.gnome.desktop.screensaver", "picture-uri")])
            self.assertIn("Offline Watch Wallet", (home / "Desktop/glacier2-bitcoin.desktop").read_text())
            self.assertEqual((home / ".local/share/glacier2/desktop-mode").read_text(), "watch-only\n")

    def test_apply_test_signers_mode(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder) / "home"
            home.mkdir()
            (home / "Desktop").mkdir()
            identity = Path(folder) / "identity"
            identity.mkdir()
            generate(identity, "regtest")
            (identity / "watch-only.dat").write_bytes(b"public-wallet-test-fixture")
            values = {}
            def settings(action, *args):
                if action == "list-schemas":
                    return "org.gnome.desktop.background"
                if action == "list-keys":
                    return "picture-uri\npicture-uri-dark\npicture-options"
                schema, key = args[:2]
                if action == "get":
                    return values.get((schema, key), "'old'")
                if action == "set":
                    values[(schema, key)] = args[2]
                    return ""
                raise AssertionError(action)
            with patch("desktop_identity.os.geteuid", return_value=1000), patch("desktop_identity.Path.home", return_value=home), \
                 patch("desktop_identity.gs", side_effect=settings), \
                 patch("desktop_identity.subprocess.check_output", return_value=str(home / "Desktop")), \
                 patch("desktop_identity.subprocess.run") as run:
                run.return_value.returncode = 0
                apply(identity, "regtest", "test-signers")
            self.assertEqual((home / ".local/share/glacier2/desktop-mode").read_text(), "test-signers\n")
            entry = (home / "Desktop/glacier2-bitcoin.desktop").read_text()
            self.assertIn("Offline Test Wallets", entry)
            self.assertIn("seven signer wallets", entry)


if __name__ == "__main__":
    unittest.main()
