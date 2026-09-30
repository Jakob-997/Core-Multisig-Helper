#!/usr/bin/env python3
"""Explicit 3-of-7 policy. Private RPC inputs use stdin, never command arguments."""
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
        payload = "".join((x if isinstance(x, str) else json.dumps(x, separators=(",", ":"))) + "\n" for x in args)
        result = subprocess.run(cmd, input=payload, text=True, capture_output=True, check=False)
        if result.returncode:
            # RPC errors can contain descriptors/private keys: do not echo stderr.
            raise RuntimeError(f"Core RPC {method} failed for {wallet or 'node'}; details suppressed")
        text = result.stdout.strip()
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return text


def checked_descriptor(core, raw, private=False):
    info = core.rpc("getdescriptorinfo", raw)
    if not info["isrange"] or not info["issolvable"] or info["hasprivatekeys"] != private:
        raise RuntimeError("Unexpected descriptor properties")
    return raw + "#" + info["checksum"] if private else info["descriptor"]


def import_pair(core, wallet, pair):
    requests = [{"desc": desc, "active": True, "internal": bool(branch), "timestamp": "now",
                 "range": [0, 999], "next_index": 0} for branch, desc in enumerate(pair)]
    results = core.rpc("importdescriptors", requests, wallet=wallet)
    if len(results) != 2 or not all(r.get("success") for r in results):
        raise RuntimeError(f"Descriptor import failed for {wallet}")
    # Core warns that a signer lacks the other six private keys: expected for multisig.
    for result in results:
        for warning in result.get("warnings", []):
            if "Not all private keys provided" not in warning:
                raise RuntimeError(f"Unexpected import warning for {wallet}; stop for review")


def create(core, chain, output):
    output = Path(output)
    if output.exists():
        raise RuntimeError("Public output already exists; refusing regeneration")
    if core.rpc("listwalletdir")["wallets"] or core.rpc("listwallets"):
        raise RuntimeError("Dedicated Core datadir must contain no wallets")
    output.mkdir(mode=0o700)
    coin = 0 if chain == "main" else 1
    path = f"m/87h/{coin}h/0h"
    records = []
    for n in range(1, 8):
        name = f"signer_{n}"
        core.rpc("createwallet", name, False, True)
        root = core.rpc("addhdkey", wallet=name)["xpub"]
        key = core.rpc("derivehdkey", path, {"hdkey": root}, wallet=name)
        if not key["origin"].startswith("[") or not key["origin"].endswith("]"):
            raise RuntimeError("Unexpected Core key-origin format")
        records.append({"wallet": name, "root": root, "origin": key["origin"], "xpub": key["xpub"]})
        print(f"Created blank signer {n} with one independent HD root", flush=True)
    if len({r["xpub"] for r in records}) != 7 or len({r["root"] for r in records}) != 7:
        raise RuntimeError("Duplicate signer key")
    raw = ["wsh(sortedmulti(3," + ",".join(r["origin"] + r["xpub"] + f"/{branch}/*" for r in records) + "))" for branch in (0, 1)]
    public = [checked_descriptor(core, desc) for desc in raw]
    core.rpc("createwallet", "watch_only", True, True)
    import_pair(core, "watch_only", public)
    if core.rpc("getwalletinfo", wallet="watch_only")["private_keys_enabled"]:
        raise RuntimeError("Watch wallet contains private keys")
    for record in records:
        # An account private descriptor is explicitly imported into its own signer.
        # Knowing the unused master root alone is insufficient for signing this policy.
        secret = core.rpc("derivehdkey", path, {"hdkey": record["root"], "private": True}, wallet=record["wallet"])
        if secret["xpub"] != record["xpub"] or secret["origin"] != record["origin"]:
            raise RuntimeError("Private/public derivation mismatch")
        private_pair = [checked_descriptor(core, desc.replace(record["xpub"], secret["xprv"]), True) for desc in raw]
        import_pair(core, record["wallet"], private_pair)
        del secret, private_pair
        # Public descriptor exports must match the watch wallet exactly.
        exported = core.rpc("listdescriptors", False, wallet=record["wallet"])["descriptors"]
        active = {d["desc"] for d in exported if d["active"]}
        if active != set(public):
            raise RuntimeError("Signer public descriptors differ from watch policy")
    samples = {}
    for branch, descriptor in enumerate(public):
        addresses = core.rpc("deriveaddresses", descriptor, [0, 2])
        for record in records + [{"wallet": "watch_only"}]:
            for address in addresses:
                info = core.rpc("getaddressinfo", address, wallet=record["wallet"])
                if not info.get("ismine") or not info.get("solvable") or not info.get("iswitness"):
                    raise RuntimeError("Core ownership/solvability validation failed")
        samples[str(branch)] = addresses
    manifest = {"schema": 1, "network": chain, "core": "32.0rc2", "threshold": 3,
                "signer_count": 7, "account_path": path, "descriptors": public,
                "signers": records, "sample_addresses": samples, "initial_range": [0, 999]}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (output / "descriptors.txt").write_text("\n".join(public) + "\n")
    print("Validated receive/change descriptors in all eight wallets.", flush=True)


if __name__ == "__main__":
    os.umask(0o077)
    if len(sys.argv) != 5:
        raise SystemExit("Usage: wallets.py BITCOIN_CLI DATADIR CHAIN PUBLIC_OUTPUT")
    try:
        create(Core(*sys.argv[1:4]), sys.argv[3], sys.argv[4])
    except Exception as exc:
        # No traceback/locals: they may hold private material.
        print(f"Wallet setup stopped: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise SystemExit(1)
