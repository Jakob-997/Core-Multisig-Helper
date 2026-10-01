#!/usr/bin/env python3
"""Disposable regtest recovery test for the Glacier 3-of-7 policy."""
import itertools
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from wallets import Core, create, import_pair


def main():
    os.umask(0o077)
    bins = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="glacier-regtest-") as folder:
        root = Path(folder)
        data = root / "data"
        data.mkdir()
        core = Core(str(bins / "bitcoin-cli"), str(data), "regtest")
        process = subprocess.Popen([
            str(bins / "bitcoind"), f"-datadir={data}", "-regtest", "-server",
            "-listen=0", "-networkactive=0", "-fallbackfee=0.0002",
            "-rpcport=18459", "-debuglogfile=0", "-printtoconsole=0"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(100):
                try:
                    core.rpc("getblockchaininfo")
                    break
                except RuntimeError:
                    if process.poll() is not None:
                        raise RuntimeError("Core failed to start")
                    time.sleep(.1)
            else:
                raise RuntimeError("Core startup timeout")

            descfile = root / "descriptors.txt"
            create(core, "regtest", descfile)
            descriptors = descfile.read_text().splitlines()

            core.rpc("createwallet", "watch_only", True, True)
            import_pair(core, "watch_only", descriptors)
            core.rpc("createwallet", "miner")
            mining = core.rpc("getnewaddress", wallet="miner")
            core.rpc("generatetoaddress", 101, mining)

            receive = core.rpc("getnewaddress", "", "bech32", wallet="watch_only")
            assert receive == core.rpc("deriveaddresses", descriptors[0], [0, 0])[0]
            core.rpc("sendtoaddress", receive, 1, wallet="miner")
            core.rpc("generatetoaddress", 1, mining)

            destination = core.rpc("getnewaddress", wallet="miner")
            psbt = core.rpc(
                "walletcreatefundedpsbt", [], [{destination: .5}], 0,
                {"fee_rate": 2, "includeWatching": True}, True, wallet="watch_only"
            )["psbt"]

            signed = []
            for n in range(1, 8):
                backup = root / f"signer_{n}.dat"
                core.rpc("backupwallet", str(backup), wallet=f"signer_{n}")
                core.rpc("unloadwallet", f"signer_{n}")
                core.rpc("restorewallet", f"restored_{n}", str(backup))
                result = core.rpc("walletprocesspsbt", psbt, wallet=f"restored_{n}")
                assert not result["complete"]
                signed.append(result["psbt"])

            for pair in itertools.combinations(signed, 2):
                assert not core.rpc("finalizepsbt", core.rpc("combinepsbt", list(pair)))["complete"]

            for indexes in itertools.combinations(range(7), 3):
                final = core.rpc("finalizepsbt", core.rpc("combinepsbt", [signed[i] for i in indexes]))
                assert final["complete"]
                assert core.rpc("testmempoolaccept", [final["hex"]])[0]["allowed"]

            print("PASS: all 21 pairs fail; all 35 triples finalize from restored signer backups.")
        finally:
            if process.poll() is None:
                core.rpc("stop")
                process.wait(timeout=30)


if __name__ == "__main__":
    main()
