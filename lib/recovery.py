#!/usr/bin/env python3
"""Recover/unlock a Glacier-2 signer from written Bytewords shares without displaying the passphrase."""
import gc
import json
import os
from pathlib import Path
import sys

from secret_material import master_xprv, recover_secret, validate_share, wallet_passphrase, wipe_bytearray
from wallets import Core


def _read_shares(helper):
    with open("/dev/tty", "r+", encoding="utf-8", buffering=1) as tty:
        tty.write("Enter one complete Bytewords share per prompt. Input is visible so you can compare it with paper.\n")
        tty.write("Share 1: ")
        first = tty.readline().strip()
        meta = validate_share(helper, first)
        shares = [meta["canonical"]]
        while len(shares) < meta["threshold"]:
            tty.write(f"Share {len(shares) + 1}: ")
            entered = tty.readline().strip()
            current = validate_share(helper, entered)
            if (current["set_id"], current["threshold"], current["count"]) != (
                meta["set_id"], meta["threshold"], meta["count"]
            ):
                raise RuntimeError("Shares are not from the same set")
            if current["canonical"] in shares:
                raise RuntimeError("Duplicate share")
            shares.append(current["canonical"])
        tty.write("\033[2J\033[H\033[3J")
        tty.flush()
    return shares


def reconstruct(helper):
    shares = _read_shares(helper)
    secret = bytearray(recover_secret(helper, shares))
    if len(secret) != 32:
        raise RuntimeError("Recovered secret length is invalid")
    return secret


def unlock(core, helper, wallet="signer", seconds=300):
    secret = reconstruct(helper)
    phrase = None
    try:
        phrase = wallet_passphrase(bytes(secret))
        core.rpc("walletpassphrase", phrase, seconds, wallet=wallet)
        print(f"{wallet} unlocked for {seconds} seconds.")
    finally:
        wipe_bytearray(secret)
        phrase = None
        gc.collect()


def recreate(core, helper, manifest_path, wallet="recovered"):
    manifest = json.loads(Path(manifest_path).read_text())
    secret = reconstruct(helper)
    phrase = xprv = None
    try:
        phrase = wallet_passphrase(bytes(secret))
        xprv = master_xprv(bytes(secret), manifest["network"])
        core.rpc("createwallet", wallet, False, True, phrase)
        core.rpc("walletpassphrase", phrase, 120, wallet=wallet)
        xpub = core.rpc("addhdkey", xprv, wallet=wallet)["xpub"]
        core.rpc("createwalletdescriptor", "bech32", {"hdkey": xpub}, wallet=wallet)
        core.rpc("walletlock", wallet=wallet)
        active = core.rpc("listdescriptors", False, wallet=wallet)["descriptors"]
        recovered = sorted(d["desc"] for d in active if d.get("active") and d["desc"].startswith("wpkh("))
        expected = sorted(manifest["descriptors"])
        if recovered != expected:
            raise RuntimeError("Recovered descriptors do not exactly match the original public manifest")
        print("Recovery verified: descriptors exactly match the original wallet.")
    finally:
        wipe_bytearray(secret)
        phrase = xprv = None
        gc.collect()


def main():
    os.umask(0o077)
    if len(sys.argv) < 6:
        raise SystemExit("Usage: recovery.py unlock|recreate BITCOIN_CLI DATADIR CHAIN SHAMIR_HELPER [MANIFEST]")
    action, cli, data, chain, helper = sys.argv[1:6]
    core = Core(cli, data, chain)
    if action == "unlock":
        unlock(core, helper)
    elif action == "recreate":
        if len(sys.argv) != 7:
            raise SystemExit("recreate requires MANIFEST")
        recreate(core, helper, sys.argv[6])
    else:
        raise SystemExit("Action must be unlock or recreate")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Recovery stopped: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise SystemExit(1)
