#!/usr/bin/env python3
"""Disposable regtest. Proves share recovery, encrypted backup restore, signing, and descriptor recreation."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from secret_material import master_xprv, recover_secret, split_secret, verify_every_combination, wallet_passphrase
from wallets import Core, create


def ready(core, process):
    for _ in range(100):
        try:
            core.rpc("getblockchaininfo")
            return
        except RuntimeError:
            if process.poll() is not None:
                raise RuntimeError("Test Core failed to start")
            time.sleep(0.1)
    raise RuntimeError("Test Core startup timeout")


def active_wpkh(core, wallet):
    rows = core.rpc("listdescriptors", False, wallet=wallet)["descriptors"]
    return sorted(d["desc"] for d in rows if d.get("active") and d["desc"].startswith("wpkh("))


def main():
    os.umask(0o077)
    if len(sys.argv) != 3:
        raise SystemExit("Usage: integration.py /path/to/bitcoin/bin /path/to/shamir-helper")
    bindir = Path(sys.argv[1]).resolve()
    helper = Path(sys.argv[2]).resolve()
    root = Path(__file__).resolve().parents[1]
    (root / "work").mkdir(exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="regtest-", dir=root / "work") as scratch:
        scratch = Path(scratch)
        data = scratch / "data"; data.mkdir()
        core = Core(str(bindir / "bitcoin-cli"), str(data), "regtest")
        process = subprocess.Popen([
            str(bindir / "bitcoind"), f"-datadir={data}", "-regtest", "-server",
            "-listen=0", "-networkactive=0", "-fallbackfee=0.0002",
            "-rpcport=18459", "-debuglogfile=0", "-printtoconsole=0"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            ready(core, process)
            secret = bytes(range(32))
            shares = split_secret(helper, secret, 3, 5)
            assert verify_every_combination(helper, shares, secret) == 10
            recovered = recover_secret(helper, [shares[0], shares[2], shares[4]])
            assert recovered == secret

            public = scratch / "public"
            recovery = scratch / "recovery"
            manifest = create(core, "regtest", public, recovery, helper,
                              policy=(3, 5), interactive=False, master_secret=recovered)
            assert manifest["backup_scheme"]["threshold"] == 3
            assert manifest["backup_scheme"]["share_count"] == 5
            assert all(x.startswith("bcrt1q") for values in manifest["sample_addresses"].values() for x in values)
            assert (recovery / "wallet.dat").stat().st_size > 0

            core.rpc("createwallet", "miner")
            mining = core.rpc("getnewaddress", wallet="miner")
            core.rpc("generatetoaddress", 101, mining)
            receive = core.rpc("getnewaddress", "", "bech32", wallet="watch_only")
            assert receive == manifest["sample_addresses"]["receive"][0]
            core.rpc("sendtoaddress", receive, 1, wallet="miner")
            core.rpc("generatetoaddress", 1, mining)
            destination = core.rpc("getnewaddress", wallet="miner")
            funded = core.rpc("walletcreatefundedpsbt", [], [{destination: 0.5}], 0,
                              {"fee_rate": 2, "includeWatching": True}, True,
                              wallet="watch_only")["psbt"]

            core.rpc("unloadwallet", "signer")
            core.rpc("restorewallet", "restored", str(recovery / "wallet.dat"))
            restored_info = core.rpc("getwalletinfo", wallet="restored")
            assert restored_info["private_keys_enabled"]
            assert restored_info.get("unlocked_until", 0) == 0

            locked_failed = False
            try:
                locked_result = core.rpc("walletprocesspsbt", funded, wallet="restored")
                locked_failed = not locked_result.get("complete", False)
            except RuntimeError:
                locked_failed = True
            assert locked_failed, "Locked encrypted wallet unexpectedly signed completely"

            phrase = wallet_passphrase(recovered)
            core.rpc("walletpassphrase", phrase, 60, wallet="restored")
            signed = core.rpc("walletprocesspsbt", funded, wallet="restored")
            final = core.rpc("finalizepsbt", signed["psbt"])
            assert final["complete"]
            accepted = core.rpc("testmempoolaccept", [final["hex"]])
            assert accepted[0]["allowed"], accepted
            core.rpc("walletlock", wallet="restored")

            # Prove the Shamir-recovered master secret recreates the exact Core descriptors.
            core.rpc("createwallet", "recreated", False, True, phrase)
            core.rpc("walletpassphrase", phrase, 60, wallet="recreated")
            xpub = core.rpc("addhdkey", master_xprv(recovered, "regtest"), wallet="recreated")["xpub"]
            core.rpc("createwalletdescriptor", "bech32", {"hdkey": xpub}, wallet="recreated")
            core.rpc("walletlock", wallet="recreated")
            assert active_wpkh(core, "recreated") == sorted(manifest["descriptors"])

            print("PASS: 3-of-5 shares reconstruct the master secret; encrypted backup restores/unlocks; "
                  "single-sig spend finalizes; recreated BIP84 descriptors match exactly.")
        finally:
            if process.poll() is None:
                try:
                    core.rpc("stop")
                finally:
                    process.wait(timeout=30)


if __name__ == "__main__":
    main()
