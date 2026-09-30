#!/usr/bin/env python3
"""Disposable regtest only. Never invokes installation, airgap, or optical writes."""
import itertools
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from wallets import Core, create


def main():
    os.umask(0o077)
    bindir = Path(sys.argv[1]).resolve()
    root = Path(__file__).resolve().parents[1]
    (root / "work").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="regtest-", dir=root / "work") as scratch:
        scratch = Path(scratch)
        data = scratch / "data"
        data.mkdir()
        core = Core(str(bindir / "bitcoin-cli"), str(data), "regtest")
        process = subprocess.Popen([str(bindir / "bitcoind"), f"-datadir={data}", "-regtest", "-server",
                                    "-listen=0", "-networkactive=0", "-fallbackfee=0.0002", "-rpcport=18459", "-debuglogfile=0",
                                    "-printtoconsole=0"], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                try:
                    core.rpc("getblockchaininfo")
                    break
                except RuntimeError:
                    if process.poll() is not None:
                        raise RuntimeError("Test Core failed to start")
                    time.sleep(0.1)
            else:
                raise RuntimeError("Test Core startup timeout")
            public = scratch / "public"
            create(core, "regtest", public)
            manifest = json.loads((public / "manifest.json").read_text())
            try:
                create(core, "regtest", scratch / "collision")
            except RuntimeError:
                pass
            else:
                raise AssertionError("Existing wallet collision was not refused")
            core.rpc("createwallet", "miner")
            mining = core.rpc("getnewaddress", wallet="miner")
            core.rpc("generatetoaddress", 101, mining)
            receive = core.rpc("getnewaddress", "", "bech32", wallet="watch_only")
            assert receive == manifest["sample_addresses"]["0"][0]
            core.rpc("sendtoaddress", receive, 1, wallet="miner")
            core.rpc("generatetoaddress", 1, mining)
            destination = core.rpc("getnewaddress", wallet="miner")
            funded = core.rpc("walletcreatefundedpsbt", [], [{destination: 0.5}], 0,
                              {"fee_rate": 2, "includeWatching": True}, True, wallet="watch_only")["psbt"]
            # Back up before unloading every original signer; only restored names sign.
            for n in range(1, 8):
                package = scratch / f"disc{n}"
                package.mkdir()
                core.rpc("backupwallet", str(package / "wallet.dat"), wallet=f"signer_{n}")
                (package / "descriptors.txt").write_text((public / "descriptors.txt").read_text())
                iso = scratch / f"disc{n}.iso"
                extracted = scratch / f"extracted{n}"
                extracted.mkdir()
                subprocess.run(["xorriso", "-as", "mkisofs", "-quiet", "-R", "-o", str(iso), str(package)],
                               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.run(["xorriso", "-osirrox", "on", "-indev", str(iso), "-extract", "/", str(extracted)],
                               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                assert (extracted / "wallet.dat").read_bytes() == (package / "wallet.dat").read_bytes()
                core.rpc("unloadwallet", f"signer_{n}")
                core.rpc("restorewallet", f"restored_{n}", str(extracted / "wallet.dat"))
            loaded = core.rpc("listwallets")
            assert not any(name.startswith("signer_") for name in loaded)
            signed = []
            for n in range(1, 8):
                result = core.rpc("walletprocesspsbt", funded, wallet=f"restored_{n}")
                assert not result["complete"]
                decoded = core.rpc("decodepsbt", result["psbt"])
                assert all(len(txin.get("partial_signatures", {})) == 1 for txin in decoded["inputs"])
                signed.append(result["psbt"])
            for combo in itertools.combinations(signed, 2):
                combined = core.rpc("combinepsbt", list(combo))
                assert not core.rpc("finalizepsbt", combined)["complete"]
            for indexes in itertools.combinations(range(7), 3):
                combined = core.rpc("combinepsbt", [signed[i] for i in indexes])
                final = core.rpc("finalizepsbt", combined)
                assert final["complete"]
                acceptance = core.rpc("testmempoolaccept", [final["hex"]])
                assert acceptance[0]["allowed"], acceptance
            print("PASS: seven independent backup/ISO restores; one signature each; all 21 pairs fail; all 35 triples finalize and pass testmempoolaccept.")
        finally:
            if process.poll() is None:
                try:
                    core.rpc("stop")
                finally:
                    process.wait(timeout=30)


if __name__ == "__main__":
    main()
