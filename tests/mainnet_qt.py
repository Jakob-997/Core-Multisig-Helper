#!/usr/bin/env python3
"""No funds or peers. Validate mainnet BIP84 derivation and Qt watch-only opening."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from wallets import Core, create


def ready(core, process):
    for _ in range(100):
        try:
            return core.rpc("getnetworkinfo")
        except RuntimeError:
            if process.poll() is not None:
                raise RuntimeError("Core startup failed")
            time.sleep(0.1)
    raise RuntimeError("Core startup timeout")


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: mainnet_qt.py /path/to/bitcoin/bin /path/to/shamir-helper")
    bins = Path(sys.argv[1]).resolve()
    helper = Path(sys.argv[2]).resolve()
    with tempfile.TemporaryDirectory(prefix="glacier-mainnet-test-") as directory:
        root = Path(directory)
        data = root / "source"; data.mkdir()
        cli = Core(str(bins / "bitcoin-cli"), str(data), "main")
        flags = ["-chain=main", "-networkactive=0", "-listen=0", "-discover=0", "-dnsseed=0", "-fixedseeds=0",
                 "-listenonion=0", "-natpmp=0", "-server=1", "-rpcport=18459", "-debuglogfile=0"]
        process = subprocess.Popen([str(bins / "bitcoind"), f"-datadir={data}", "-printtoconsole=0", *flags],
                                   stderr=subprocess.PIPE)
        try:
            ready(cli, process)
            create(cli, "main", root / "public", root / "recovery", helper,
                   policy=(2, 3), interactive=False, master_secret=bytes(range(32)))
            manifest = json.loads((root / "public/manifest.json").read_text())
            assert all(a.startswith("bc1q") for addresses in manifest["sample_addresses"].values() for a in addresses)
            assert len(manifest["descriptors"]) == 2
            assert all(d.startswith("wpkh(") for d in manifest["descriptors"])
            backup = root / "watch-only.dat"
            cli.rpc("backupwallet", str(backup), wallet="watch_only")
        finally:
            if process.poll() is None:
                cli.rpc("stop")
                process.wait(timeout=30)

        qtdata = root / "qt"
        wallet = qtdata / "wallets/watch_only"
        wallet.mkdir(parents=True)
        shutil.copyfile(backup, wallet / "wallet.dat")
        qtcli = Core(str(bins / "bitcoin-cli"), str(qtdata), "main")
        process = subprocess.Popen([str(bins / "bitcoin-qt"), f"-datadir={qtdata}",
                                    "-wallet=watch_only", *flags], stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE, env=dict(os.environ, QT_QPA_PLATFORM="minimal"))
        try:
            info = ready(qtcli, process)
            assert info["networkactive"] is False and info["connections"] == 0
            assert qtcli.rpc("getwalletinfo", wallet="watch_only")["private_keys_enabled"] is False
            assert qtcli.rpc("getnewaddress", "", "bech32", wallet="watch_only").startswith("bc1q")
            print("PASS: mainnet Core BIP84 descriptors and Qt watch-only copy; networking disabled, zero peers.")
        finally:
            if process.poll() is None:
                qtcli.rpc("stop")
                process.wait(timeout=30)


if __name__ == "__main__":
    main()
