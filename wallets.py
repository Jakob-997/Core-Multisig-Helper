#!/usr/bin/env python3
"""Create seven Bitcoin Core signers for one 3-of-7 descriptor policy."""
import json
import os
from pathlib import Path
import subprocess
import sys


class Core:
    def __init__(self, cli, data, chain):
        self.args = [cli, f"-datadir={data}", f"-chain={chain}", "-rpcport=18459"]

    def rpc(self, method, *args, wallet=None):
        cmd = self.args + ([f"-rpcwallet={wallet}"] if wallet else []) + ["-stdin", method]
        stdin = "".join((x if isinstance(x, str) else json.dumps(x, separators=(",", ":"))) + "\n" for x in args)
        result = subprocess.run(cmd, input=stdin, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(f"Core RPC {method} failed for {wallet or 'node'}; details suppressed")
        text = result.stdout.strip()
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return text


def descriptor(core, raw, private=False):
    info = core.rpc("getdescriptorinfo", raw)
    if not info["isrange"] or not info["issolvable"] or info["hasprivatekeys"] != private:
        raise RuntimeError("Unexpected descriptor")
    return raw + "#" + info["checksum"] if private else info["descriptor"]


def import_pair(core, wallet, pair):
    requests = [
        {"desc": desc, "active": True, "internal": bool(branch),
         "timestamp": "now", "range": [0, 999], "next_index": 0}
        for branch, desc in enumerate(pair)
    ]
    results = core.rpc("importdescriptors", requests, wallet=wallet)
    if len(results) != 2 or not all(x.get("success") for x in results):
        raise RuntimeError(f"Descriptor import failed for {wallet}")


def create(core, chain, output):
    output = Path(output)
    if output.exists() or core.rpc("listwalletdir")["wallets"] or core.rpc("listwallets"):
        raise RuntimeError("Existing wallet state; refusing regeneration")

    path = f"m/87h/{0 if chain == 'main' else 1}h/0h"
    keys = []
    for n in range(1, 8):
        wallet = f"signer_{n}"
        core.rpc("createwallet", wallet, False, True)
        root = core.rpc("addhdkey", wallet=wallet)["xpub"]
        account = core.rpc("derivehdkey", path, {"hdkey": root}, wallet=wallet)
        keys.append((wallet, root, account["origin"], account["xpub"]))

    if len({xpub for _, _, _, xpub in keys}) != 7:
        raise RuntimeError("Duplicate signer key")

    raw = [
        "wsh(sortedmulti(3," + ",".join(origin + xpub + f"/{branch}/*" for _, _, origin, xpub in keys) + "))"
        for branch in (0, 1)
    ]
    public = [descriptor(core, x) for x in raw]

    for wallet, root, origin, xpub in keys:
        secret = core.rpc("derivehdkey", path, {"hdkey": root, "private": True}, wallet=wallet)
        if secret["origin"] != origin or secret["xpub"] != xpub:
            raise RuntimeError("Private/public derivation mismatch")
        import_pair(core, wallet, [descriptor(core, x.replace(xpub, secret["xprv"]), True) for x in raw])

    output.write_text("\n".join(public) + "\n")
    print("Created seven independent signers and one 3-of-7 descriptor policy.", flush=True)


if __name__ == "__main__":
    os.umask(0o077)
    if len(sys.argv) != 5:
        raise SystemExit("Usage: wallets.py BITCOIN_CLI DATADIR CHAIN DESCRIPTORS_FILE")
    try:
        create(Core(*sys.argv[1:4]), sys.argv[3], sys.argv[4])
    except Exception as exc:
        print(f"Wallet setup stopped: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise SystemExit(1)
