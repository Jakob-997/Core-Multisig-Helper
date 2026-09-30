#!/usr/bin/env python3
"""Local recognition cues, not attestation or cryptographic anti-exfiltration."""
import ast
import colorsys
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys


def generate(directory, chain):
    from PIL import Image, ImageDraw, ImageFont
    directory = Path(directory)
    target = directory / "identity.json"
    if target.exists() or (directory / "wallpaper.png").exists():
        raise RuntimeError("Identity already exists; refusing to change the recognition cue")
    token = secrets.token_hex(10).upper()
    code = "-".join(token[i:i + 4] for i in range(0, 20, 4))
    rgb = tuple(round(c * 255) for c in colorsys.hls_to_rgb(secrets.randbelow(360) / 360, 0.22, 0.6))
    color = "#" + "".join(f"{c:02X}" for c in rgb)
    identity = {"schema": 1, "code": code, "color": color, "network": chain,
                "purpose": "Visual recognition only; not proof of integrity or anti-exfiltration"}
    image = Image.new("RGB", (1920, 1080), rgb)
    draw = ImageDraw.Draw(image)
    fontdir = Path("/usr/share/fonts/truetype/dejavu")
    def line(text, y, size, bold=False):
        font = ImageFont.truetype(str(fontdir / ("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf")), size)
        draw.text((960, y), text, fill="white", font=font, anchor="mm")
    line("OFFLINE LAPTOP", 300, 76, True)
    line("COLD STORAGE", 395, 76, True)
    line("BITCOIN MAINNET" if chain == "main" else f"BITCOIN {chain.upper()} — TEST NETWORK", 490, 32)
    line("RECOGNITION CODE", 605, 24)
    line(code, 665, 50, True)
    line(f"COLOR {color}  •  KEEP THIS COMPUTER OFFLINE", 760, 24)
    line("Compare with your separate paper record before use.", 825, 24)
    line("Visual cue only — not proof the system is unchanged.", 870, 22)
    image.save(directory / "wallpaper.png")
    target.write_text(json.dumps(identity, indent=2) + "\n")
    for path in (directory / "wallpaper.png", target):
        path.chmod(0o644)
    return identity


def gs(*args):
    return subprocess.check_output(["gsettings", *args], text=True).strip()


def apply(directory, chain):
    if os.geteuid() == 0:
        raise RuntimeError("Apply desktop preferences as the desktop user, not root")
    directory = Path(directory).resolve()
    identity = json.loads((directory / "identity.json").read_text())
    if identity["network"] != chain:
        raise RuntimeError("Identity network mismatch")
    base = Path.home() / ".local/share/glacier2"
    base.mkdir(mode=0o700, parents=True, exist_ok=False)
    data = base / "core"
    # Core's wallet directory is chain-specific; mainnet uses the datadir itself.
    chain_dir = data if chain == "main" else data / chain
    wallet = chain_dir / "wallets/watch_only"
    wallet.mkdir(parents=True, mode=0o700)
    shutil.copyfile(directory / "watch-only.dat", wallet / "wallet.dat")
    (wallet / "wallet.dat").chmod(0o600)
    (data / "bitcoin.conf").write_text("networkactive=0\nlisten=0\ndiscover=0\ndnsseed=0\nfixedseeds=0\nlistenonion=0\nnatpmp=0\nserver=0\n")
    (base / "chain").write_text(chain + "\n")
    uri = (directory / "wallpaper.png").as_uri()
    changes = []
    def setting(schema, key, value):
        keys = gs("list-keys", schema).splitlines()
        if key not in keys:
            return False
        old = gs("get", schema, key)
        gs("set", schema, key, value)
        if gs("get", schema, key) != value:
            raise RuntimeError(f"Desktop setting readback failed: {schema} {key}")
        changes.append({"schema": schema, "key": key, "previous": old, "applied": value})
        return True
    setting("org.gnome.desktop.background", "picture-uri", repr(uri))
    setting("org.gnome.desktop.background", "picture-uri-dark", repr(uri))
    setting("org.gnome.desktop.background", "picture-options", "'zoom'")
    schemas = gs("list-schemas").splitlines()
    if "org.gnome.desktop.screensaver" in schemas:
        setting("org.gnome.desktop.screensaver", "picture-uri", repr(uri))
    # Modern GNOME uses a blurred desktop background at lock; text may be hidden.
    print("Desktop set. Lock screen inherits this image on modern GNOME; text may be blurred.")
    desktop_id = "glacier2-bitcoin.desktop"
    applications = Path.home() / ".local/share/applications"
    applications.mkdir(parents=True, exist_ok=True)
    entry = ("[Desktop Entry]\nType=Application\nName=Bitcoin Core — Offline Watch Wallet\n"
             "Comment=Glacier-2 public watch-only wallet; networking disabled\n"
             "Exec=/opt/glacier2/identity/launch-qt\nIcon=/opt/glacier2/identity/bitcoin-core.svg\nTerminal=false\n"
             "Categories=Office;Finance;\nStartupWMClass=Bitcoin-qt\n")
    app = applications / desktop_id
    with app.open("x") as handle:
        handle.write(entry)
    app.chmod(0o755)
    subprocess.run(["desktop-file-validate", str(app)], check=True)
    desktop = Path(subprocess.check_output(["xdg-user-dir", "DESKTOP"], text=True).strip())
    if desktop.is_absolute() and desktop != Path.home() and desktop.is_dir():
        shortcut = desktop / desktop_id
        with shortcut.open("x") as handle:
            handle.write(entry)
        shortcut.chmod(0o755)
        trusted = subprocess.run(["gio", "set", str(shortcut), "metadata::trusted", "true"], capture_output=True)
        if trusted.returncode:
            print("Desktop shortcut created; use right-click > Allow Launching if required.")
    if "org.gnome.shell" in schemas:
        favorites = ast.literal_eval(gs("get", "org.gnome.shell", "favorite-apps").removeprefix("@as "))
        if desktop_id not in favorites:
            try:
                gs("set", "org.gnome.shell", "favorite-apps", repr(favorites + [desktop_id]))
                print("Bitcoin Core added to GNOME favorites.")
            except subprocess.CalledProcessError:
                print("Could not pin favorites; use the installed Applications shortcut.")
    (base / "desktop-settings.json").write_text(json.dumps(changes, indent=2) + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[3] not in {"main", "regtest", "signet"}:
        raise SystemExit("Usage: desktop_identity.py generate|apply DIRECTORY main|regtest|signet")
    {"generate": generate, "apply": apply}[sys.argv[1]](sys.argv[2], sys.argv[3])
