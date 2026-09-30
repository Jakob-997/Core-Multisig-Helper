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
            image = Image.open(Path(folder) / "wallpaper.png")
            self.assertEqual(image.size, (1920, 1080))
            before = (Path(folder) / "identity.json").read_bytes()
            with self.assertRaises(RuntimeError):
                generate(folder, "main")
            self.assertEqual((Path(folder) / "identity.json").read_bytes(), before)

    def _apply(self, mode):
        folder = tempfile.TemporaryDirectory()
        root = Path(folder.name)
        home = root / "home"; home.mkdir(); (home / "Desktop").mkdir()
        identity = root / "identity"; identity.mkdir()
        generate(identity, "main")
        (identity / "watch-only.dat").write_bytes(b"public-wallet-test-fixture")
        values = {}
        def settings(action, *args):
            if action == "list-schemas": return "org.gnome.desktop.background\norg.gnome.desktop.screensaver\norg.gnome.shell"
            if action == "list-keys": return "picture-uri\npicture-uri-dark\npicture-options"
            schema, key = args[:2]
            if action == "get": return values.get((schema, key), "[]" if key == "favorite-apps" else "'old'")
            if action == "set": values[(schema, key)] = args[2]; return ""
            raise AssertionError(action)
        with patch("desktop_identity.os.geteuid", return_value=1000), patch("desktop_identity.Path.home", return_value=home), \
             patch("desktop_identity.gs", side_effect=settings), \
             patch("desktop_identity.subprocess.check_output", return_value=str(home / "Desktop")), \
             patch("desktop_identity.subprocess.run") as run:
            run.return_value.returncode = 0
            apply(identity, "main", mode)
        return folder, home

    def test_watch_only_mode(self):
        folder, home = self._apply("watch-only")
        try:
            self.assertEqual((home / ".local/share/glacier2/desktop-mode").read_text(), "watch-only\n")
            self.assertIn("Offline Watch Wallet", (home / "Desktop/glacier2-bitcoin.desktop").read_text())
        finally:
            folder.cleanup()

    def test_single_signer_test_mode(self):
        folder, home = self._apply("test-signer")
        try:
            self.assertEqual((home / ".local/share/glacier2/desktop-mode").read_text(), "test-signer\n")
            entry = (home / "Desktop/glacier2-bitcoin.desktop").read_text()
            self.assertIn("Offline Test Wallets", entry)
            self.assertIn("one encrypted signer wallet", entry)
        finally:
            folder.cleanup()


if __name__ == "__main__":
    unittest.main()
