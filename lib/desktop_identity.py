#!/usr/bin/env python3
"""Generate/apply Glacier's local recognition cue and GNOME watch-wallet desktop."""
import ast, colorsys, json, os, secrets, shutil, subprocess, sys
from pathlib import Path

def gs(*args):
    return subprocess.check_output(["gsettings", *args], text=True).strip()

def generate(folder, chain):
    from PIL import Image, ImageDraw, ImageFont
    folder = Path(folder)
    identity_file, wallpaper = folder / "identity.json", folder / "wallpaper.png"
    if identity_file.exists() or wallpaper.exists():
        raise RuntimeError("Identity already exists; refusing to change the recognition cue")

    token = secrets.token_hex(10).upper()
    code = "-".join(token[i:i+4] for i in range(0, 20, 4))
    rgb = tuple(round(c * 255) for c in colorsys.hls_to_rgb(secrets.randbelow(360) / 360, .22, .6))
    color = "#" + "".join(f"{c:02X}" for c in rgb)
    identity = {"schema": 1, "code": code, "color": color, "network": chain,
                "purpose": "Visual recognition only; not proof of integrity or anti-exfiltration"}

    image, fontdir = Image.new("RGB", (1920, 1080), rgb), Path("/usr/share/fonts/truetype/dejavu")
    draw = ImageDraw.Draw(image)
    for text, y, size, bold in [
        ("OFFLINE LAPTOP", 300, 76, True),
        ("COLD STORAGE", 395, 76, True),
        ("BITCOIN MAINNET" if chain == "main" else f"BITCOIN {chain.upper()} — TEST NETWORK", 490, 32, False),
        ("RECOGNITION CODE", 605, 24, False), (code, 665, 50, True),
        (f"COLOR {color}  •  KEEP THIS COMPUTER OFFLINE", 760, 24, False),
        ("Compare with your separate paper record before use.", 825, 24, False),
        ("Visual cue only — not proof the system is unchanged.", 870, 22, False),
    ]:
        font = ImageFont.truetype(str(fontdir / ("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf")), size)
        draw.text((960, y), text, fill="white", font=font, anchor="mm")
    image.save(wallpaper)
    identity_file.write_text(json.dumps(identity, indent=2) + "\n")
    wallpaper.chmod(0o644); identity_file.chmod(0o644)
    return identity

def apply(folder, chain, mode="watch-only"):
    if mode not in {"watch-only", "test-signers"} or os.geteuid() == 0:
        raise RuntimeError("Invalid desktop mode or root desktop invocation")
    folder = Path(folder).resolve()
    identity = json.loads((folder / "identity.json").read_text())
    if identity["network"] != chain:
        raise RuntimeError("Identity network mismatch")

    base = Path.home() / ".local/share/glacier2"
    base.mkdir(mode=0o700, parents=True, exist_ok=False)
    data = base / "core"
    wallet = (data if chain == "main" else data / chain) / "wallets/watch_only"
    wallet.mkdir(parents=True, mode=0o700)
    shutil.copyfile(folder / "watch-only.dat", wallet / "wallet.dat")
    (wallet / "wallet.dat").chmod(0o600)
    (data / "bitcoin.conf").write_text(
        "networkactive=0\nlisten=0\ndiscover=0\ndnsseed=0\nfixedseeds=0\nlistenonion=0\nnatpmp=0\nserver=0\n")
    (base / "chain").write_text(chain + "\n")
    (base / "desktop-mode").write_text(mode + "\n")

    schemas, changes = set(gs("list-schemas").splitlines()), []
    def setting(schema, key, value):
        if schema not in schemas or key not in gs("list-keys", schema).splitlines():
            return
        old = gs("get", schema, key)
        gs("set", schema, key, value)
        if gs("get", schema, key) != value:
            raise RuntimeError(f"Desktop setting readback failed: {schema} {key}")
        changes.append({"schema": schema, "key": key, "previous": old, "applied": value})

    uri = repr((folder / "wallpaper.png").as_uri())
    for schema, key, value in [
        ("org.gnome.desktop.background", "picture-uri", uri),
        ("org.gnome.desktop.background", "picture-uri-dark", uri),
        ("org.gnome.desktop.background", "picture-options", "'zoom'"),
        ("org.gnome.desktop.screensaver", "picture-uri", uri),
    ]:
        setting(schema, key, value)
    print("Desktop set. Lock screen inherits this image on modern GNOME; text may be blurred.")

    desktop_id = "glacier2-bitcoin.desktop"
    test = mode == "test-signers"
    entry = (
        "[Desktop Entry]\nType=Application\n"
        f"Name=Bitcoin Core — Offline {'Test Wallets' if test else 'Watch Wallet'}\n"
        f"Comment={'Glacier-2 test mode: watch-only plus seven signer wallets' if test else 'Glacier-2 public watch-only wallet'}; networking disabled\n"
        "Exec=/opt/glacier2/identity/launch-qt\nIcon=/opt/glacier2/identity/bitcoin-core.svg\n"
        "Terminal=false\nCategories=Office;Finance;\nStartupWMClass=Bitcoin-qt\n"
    )
    apps = Path.home() / ".local/share/applications"
    apps.mkdir(parents=True, exist_ok=True)
    app = apps / desktop_id
    app.write_text(entry); app.chmod(0o755)
    subprocess.run(["desktop-file-validate", str(app)], check=True)

    desktop = Path(subprocess.check_output(["xdg-user-dir", "DESKTOP"], text=True).strip())
    if desktop.is_absolute() and desktop != Path.home() and desktop.is_dir():
        shortcut = desktop / desktop_id
        with shortcut.open("x") as f: f.write(entry)
        shortcut.chmod(0o755)
        if subprocess.run(["gio", "set", str(shortcut), "metadata::trusted", "true"], capture_output=True).returncode:
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
    if len(sys.argv) not in {4, 5} or sys.argv[3] not in {"main", "regtest", "signet"}:
        raise SystemExit("Usage: desktop_identity.py generate|apply DIRECTORY main|regtest|signet [watch-only|test-signers]")
    action, folder, chain = sys.argv[1:4]
    if action == "generate" and len(sys.argv) == 4:
        generate(folder, chain)
    elif action == "apply":
        apply(folder, chain, sys.argv[4] if len(sys.argv) == 5 else "watch-only")
    else:
        raise SystemExit("Invalid action or arguments")
