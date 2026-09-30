#!/usr/bin/env python3
"""Create one encrypted single-sig Core wallet and verified Shamir paper backups."""
import gc
import itertools
import json
import os
from pathlib import Path
import subprocess
import sys

from secret_material import (
    POLICIES,
    canonical_share,
    generate_master_secret,
    master_xprv,
    recover_secret,
    split_secret,
    validate_share,
    verify_every_combination,
    wallet_passphrase,
    wipe_bytearray,
)


class Core:
    def __init__(self, cli, data, chain):
        self.args = [cli, f"-datadir={data}", f"-chain={chain}", "-rpcport=18459"]

    def rpc(self, method, *args, wallet=None):
        cmd = self.args + ([f"-rpcwallet={wallet}"] if wallet else []) + ["-stdin", method]
        payload = "".join((x if isinstance(x, str) else json.dumps(x, separators=(",", ":"))) + "\n" for x in args)
        result = subprocess.run(cmd, input=payload, text=True, capture_output=True, check=False)
        if result.returncode:
            raise RuntimeError(f"Core RPC {method} failed for {wallet or 'node'}; details suppressed")
        text = result.stdout.strip()
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return text


def _clear_tty(tty):
    tty.write("\033[2J\033[H\033[3J")
    tty.flush()


def choose_policy(tty):
    tty.write(
        "\nChoose how many written shares are required to recover the wallet:\n"
        "  1) 2 of 3\n"
        "  2) 3 of 5\n"
        "  3) 3 of 7\n"
        "Selection: "
    )
    tty.flush()
    choice = tty.readline().strip()
    mapping = {"1": (2, 3), "2": (3, 5), "3": (3, 7)}
    if choice not in mapping:
        raise RuntimeError("Invalid backup policy selection")
    return mapping[choice]


def verify_written_shares(helper, shares, tty):
    verified = []
    for number, share in enumerate(shares, 1):
        while True:
            _clear_tty(tty)
            tty.write(
                f"SECRET SHARE {number} OF {len(shares)}\n\n"
                f"{share}\n\n"
                "Write this entire line exactly as shown. Store this share separately from the others.\n"
                "Press Enter only after you have finished writing it down: "
            )
            tty.flush()
            tty.readline()
            _clear_tty(tty)
            tty.write(
                f"Verification for share {number}: type the share from your written copy, then press Enter.\n"
                "Share: "
            )
            tty.flush()
            entered = canonical_share(tty.readline())
            try:
                meta = validate_share(helper, entered)
            except RuntimeError:
                meta = None
            if meta and entered == share:
                tty.write("Verified. Press Enter to continue.\n")
                tty.flush()
                tty.readline()
                verified.append(entered)
                break
            tty.write(
                "\nThat entry did not exactly match the generated share or failed its checksum.\n"
                "Nothing was accepted. Press Enter to display this same share again.\n"
            )
            tty.flush()
            tty.readline()
    _clear_tty(tty)
    return verified


def import_public_pair(core, wallet, descriptors):
    requests = [
        {
            "desc": d["desc"],
            "active": True,
            "internal": bool(d["internal"]),
            "timestamp": "now",
            "range": [0, 999],
            "next_index": 0,
        }
        for d in descriptors
    ]
    result = core.rpc("importdescriptors", requests, wallet=wallet)
    if len(result) != 2 or not all(item.get("success") for item in result):
        raise RuntimeError("Watch-only descriptor import failed")
    for item in result:
        if item.get("warnings"):
            raise RuntimeError("Unexpected descriptor import warning")


def create(core, chain, public_output, recovery_output, helper, policy=None, interactive=True, master_secret=None):
    public_output = Path(public_output)
    recovery_output = Path(recovery_output)
    helper = Path(helper)
    if public_output.exists() or recovery_output.exists():
        raise RuntimeError("Output already exists; refusing regeneration")
    if core.rpc("listwalletdir")["wallets"] or core.rpc("listwallets"):
        raise RuntimeError("Dedicated Core datadir must contain no wallets")
    if not helper.is_file():
        raise RuntimeError("Pinned Shamir helper is missing")

    if interactive:
        with open("/dev/tty", "r+", encoding="utf-8", buffering=1) as tty:
            threshold, count = choose_policy(tty)
    else:
        if policy not in POLICIES:
            raise RuntimeError("A supported noninteractive policy is required")
        threshold, count = policy

    public_output.mkdir(mode=0o700)
    recovery_output.mkdir(mode=0o700)

    if master_secret is not None:
        if interactive or len(master_secret) != 32:
            raise RuntimeError("Test master secret is only permitted for noninteractive 32-byte tests")
        secret = bytearray(master_secret)
    else:
        secret = bytearray(generate_master_secret())
    passphrase = None
    xprv = None
    shares = None
    typed = None
    try:
        passphrase = wallet_passphrase(bytes(secret))
        xprv = master_xprv(bytes(secret), chain)

        core.rpc("createwallet", "signer", False, True, passphrase)
        info = core.rpc("getwalletinfo", wallet="signer")
        if not info["private_keys_enabled"]:
            raise RuntimeError("Signer wallet does not contain private keys")

        core.rpc("walletpassphrase", passphrase, 120, wallet="signer")
        added = core.rpc("addhdkey", xprv, wallet="signer")
        xpub = added.get("xpub")
        if not isinstance(xpub, str) or not xpub.startswith(("xpub", "tpub")):
            raise RuntimeError("Core did not accept the deterministic HD root")
        created = core.rpc("createwalletdescriptor", "bech32", {"hdkey": xpub}, wallet="signer")
        if len(created.get("descs", [])) != 2:
            raise RuntimeError("Core did not create both BIP84 descriptors")
        core.rpc("walletlock", wallet="signer")

        listed = core.rpc("listdescriptors", False, wallet="signer")["descriptors"]
        descriptors = [d for d in listed if d.get("active") and d["desc"].startswith("wpkh(")]
        descriptors.sort(key=lambda d: bool(d["internal"]))
        if len(descriptors) != 2 or {bool(d["internal"]) for d in descriptors} != {False, True}:
            raise RuntimeError("Unexpected active BIP84 descriptor set")

        core.rpc("createwallet", "watch_only", True, True)
        import_public_pair(core, "watch_only", descriptors)
        if core.rpc("getwalletinfo", wallet="watch_only")["private_keys_enabled"]:
            raise RuntimeError("Watch-only wallet contains private keys")

        samples = {}
        for d in descriptors:
            branch = "change" if d["internal"] else "receive"
            addresses = core.rpc("deriveaddresses", d["desc"], [0, 2])
            if len(addresses) != 3:
                raise RuntimeError("Address derivation returned an unexpected count")
            for address in addresses:
                if chain == "main" and not address.startswith("bc1q"):
                    raise RuntimeError("Mainnet descriptor did not produce native-SegWit addresses")
                for wallet in ("signer", "watch_only"):
                    ai = core.rpc("getaddressinfo", address, wallet=wallet)
                    if not ai.get("ismine") or not ai.get("solvable") or not ai.get("iswitness"):
                        raise RuntimeError("Core ownership/solvability validation failed")
            samples[branch] = addresses

        shares = split_secret(helper, bytes(secret), threshold, count)
        checked = verify_every_combination(helper, shares, bytes(secret))
        expected_combinations = len(list(itertools.combinations(range(count), threshold)))
        if checked != expected_combinations:
            raise RuntimeError("Not all threshold combinations were checked")

        if interactive:
            with open("/dev/tty", "r+", encoding="utf-8", buffering=1) as tty:
                typed = verify_written_shares(helper, shares, tty)
                if len(typed) != count:
                    raise RuntimeError("Not every share was verified")
                # Reconstruct from the first threshold written copies as a final end-to-end test.
                if recover_secret(helper, typed[:threshold]) != bytes(secret):
                    raise RuntimeError("Written-share recovery test failed")
                tty.write(
                    f"All {count} shares verified. Any {threshold} different shares recover this wallet.\n"
                    "No share text has been written to disk by Glacier-2.\n"
                )
                tty.flush()
        else:
            typed = list(shares)

        core.rpc("backupwallet", str(recovery_output / "wallet.dat"), wallet="signer")
        if not (recovery_output / "wallet.dat").stat().st_size:
            raise RuntimeError("Encrypted wallet backup is empty")

        manifest = {
            "schema": 2,
            "network": chain,
            "core": "32.0rc2",
            "wallet_type": "single-sig native SegWit descriptor wallet",
            "address_type": "bech32",
            "derivation": "BIP84 via Bitcoin Core createwalletdescriptor",
            "backup_scheme": {
                "implementation": "Blockchain Commons bc-shamir + Bytewords",
                "threshold": threshold,
                "share_count": count,
                "secret_bytes": 32,
                "shares_written_to_disk": False,
            },
            "wallet_encryption": "HMAC-SHA256 domain-separated passphrase derived from the same 32-byte master secret",
            "root_xpub": xpub,
            "descriptors": [d["desc"] for d in descriptors],
            "sample_addresses": samples,
            "initial_range": [0, 999],
        }
        (public_output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        (public_output / "descriptors.txt").write_text("\n".join(d["desc"] for d in descriptors) + "\n")
        (recovery_output / "README.txt").write_text(
            "This wallet.dat is encrypted. It does not contain the written Shamir shares.\n"
            f"Recover the 32-byte master secret from any {threshold} of {count} shares to recreate the wallet encryption passphrase and BIP32 master key.\n"
        )
        print(
            f"Created and validated one encrypted single-sig BIP84 wallet; "
            f"verified all {checked} {threshold}-of-{count} share combinations.",
            flush=True,
        )
        return manifest
    finally:
        wipe_bytearray(secret)
        if shares is not None:
            shares = ["" for _ in shares]
        if typed is not None:
            typed = ["" for _ in typed]
        xprv = None
        passphrase = None
        gc.collect()


if __name__ == "__main__":
    os.umask(0o077)
    if len(sys.argv) != 8:
        raise SystemExit(
            "Usage: wallets.py BITCOIN_CLI DATADIR CHAIN PUBLIC_OUTPUT RECOVERY_OUTPUT SHAMIR_HELPER TEST_MODE"
        )
    cli, data, chain, public_output, recovery_output, helper, test_mode = sys.argv[1:]
    try:
        create(
            Core(cli, data, chain),
            chain,
            public_output,
            recovery_output,
            helper,
            policy=(2, 3) if test_mode == "1" else None,
            interactive=test_mode != "1",
        )
    except Exception as exc:
        print(f"Wallet setup stopped: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise SystemExit(1)
