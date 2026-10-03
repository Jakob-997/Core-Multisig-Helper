#!/usr/bin/env python3
import json, shutil, subprocess, sys, time
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit("usage: ./multisig.py M N /path/to/bitcoin/bin")

M, N = map(int, sys.argv[1:3])
BIN = Path(sys.argv[3]).resolve()
STATE = Path("/dev/shm/core-multisig")
DATA, OUT = STATE / "data", STATE / "backups"
BITCOIND, CLI = BIN / "bitcoind", BIN / "bitcoin-cli"

if not (1 <= M <= N <= 20):
    raise SystemExit("require 1 <= M <= N <= 20")
if STATE.exists():
    raise SystemExit(f"{STATE} already exists; reboot or remove it before generating a new wallet")
if not BITCOIND.is_file() or not CLI.is_file():
    raise SystemExit("bitcoin-cli and bitcoind were not found in the supplied Bitcoin Core bin directory")

DATA.mkdir(parents=True)
OUT.mkdir()
subprocess.run([BITCOIND, f"-datadir={DATA}", "-daemon", "-networkactive=0", "-listen=0"], check=True)

def cli(*args, wallet=None):
    cmd = [CLI, f"-datadir={DATA}"]
    if wallet:
        cmd += [f"-rpcwallet={wallet}"]
    return json.loads(subprocess.check_output(cmd + list(args), text=True))

try:
    for _ in range(100):
        try:
            cli("getblockchaininfo")
            break
        except subprocess.CalledProcessError:
            time.sleep(.1)
    else:
        raise RuntimeError("Bitcoin Core did not start")

    keys = []
    for i in range(1, N + 1):
        w = f"signer_{i}"
        cli("createwallet", w, "false", "true")
        root = cli("addhdkey", wallet=w)["xpub"]
        key = cli("derivehdkey", "m/87h/0h/0h", json.dumps({"hdkey": root, "private": True}), wallet=w)
        keys.append(key)

    body = "wsh(sortedmulti(" + str(M) + "," + ",".join(
        f"{k['origin']}{k['xpub']}/<0;1>/*" for k in keys
    ) + "))"
    desc = body + "#" + cli("getdescriptorinfo", body)["checksum"]

    cli("createwallet", "watch_only", "true", "true")
    req = json.dumps([{"desc": desc, "active": True, "timestamp": 0}])
    if not cli("importdescriptors", req, wallet="watch_only")[0]["success"]:
        raise RuntimeError("watch-only descriptor import failed")

    for i, k in enumerate(keys, 1):
        private = body.replace(k["xpub"], k["xprv"]) + "#" + cli(
            "getdescriptorinfo", body.replace(k["xpub"], k["xprv"])
        )["checksum"]
        req = json.dumps([{"desc": private, "active": True, "timestamp": 0}])
        if not cli("importdescriptors", req, wallet=f"signer_{i}")[0]["success"]:
            raise RuntimeError(f"signer {i} descriptor import failed")
        cli("backupwallet", str(OUT / f"signer_{i}.dat"), wallet=f"signer_{i}")

    cli("backupwallet", str(OUT / "watch_only.dat"), wallet="watch_only")
    (OUT / "descriptor.txt").write_text(desc + "\n")
    print(f"Done. Burn the files in {OUT} to {N + 1} separately labeled CD-Rs.")
finally:
    subprocess.run([CLI, f"-datadir={DATA}", "stop"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
