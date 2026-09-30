#!/usr/bin/env python3
"""Small deterministic secret layer. Shamir and Bytewords live in the pinned C helper."""
import hashlib
import hmac
import itertools
import os
from pathlib import Path
import subprocess

POLICIES = ((2, 3), (3, 5), (3, 7))
SECP256K1_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
B58 = b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
WALLET_KDF_LABEL = b"Glacier-2 Core wallet encryption v1"


def generate_master_secret():
    secret = os.getrandom(32)
    if len(secret) != 32:
        raise RuntimeError("OS CSPRNG returned the wrong length")
    return secret


def _base58check(payload):
    raw = payload + hashlib.sha256(hashlib.sha256(payload).digest()).digest()[:4]
    value = int.from_bytes(raw, "big")
    encoded = bytearray()
    while value:
        value, rem = divmod(value, 58)
        encoded.append(B58[rem])
    zeros = len(raw) - len(raw.lstrip(b"\0"))
    encoded.extend(B58[0] for _ in range(zeros))
    encoded.reverse()
    return bytes(encoded).decode("ascii")


def master_xprv(secret, chain):
    if len(secret) != 32:
        raise ValueError("master secret must be 32 bytes")
    digest = hmac.new(b"Bitcoin seed", secret, hashlib.sha512).digest()
    key = digest[:32]
    scalar = int.from_bytes(key, "big")
    if not 1 <= scalar < SECP256K1_ORDER:
        raise RuntimeError("BIP32 produced an invalid master key; start over before creating backups")
    version = bytes.fromhex("0488ade4" if chain == "main" else "04358394")
    serialized = version + b"\0" + (b"\0" * 4) + (b"\0" * 4) + digest[32:] + b"\0" + key
    if len(serialized) != 78:
        raise AssertionError("BIP32 serialization length")
    return _base58check(serialized)


def wallet_passphrase(secret):
    if len(secret) != 32:
        raise ValueError("master secret must be 32 bytes")
    return hmac.new(secret, WALLET_KDF_LABEL, hashlib.sha256).hexdigest()


def canonical_share(text):
    return " ".join(text.strip().lower().split())


def _run(helper, args, data, text=False):
    result = subprocess.run([str(Path(helper)), *args], input=data, text=text,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    if result.returncode:
        raise RuntimeError("Secret helper rejected the operation; details suppressed")
    return result.stdout


def validate_share(helper, share):
    canonical = canonical_share(share)
    out = _run(helper, ["validate"], canonical + "\n", text=True).strip().split()
    if len(out) != 4:
        raise RuntimeError("Unexpected share metadata")
    set_id, threshold, count, number = out
    threshold, count, number = int(threshold), int(count), int(number)
    if (threshold, count) not in POLICIES or not 1 <= number <= count:
        raise RuntimeError("Unsupported share metadata")
    return {"set_id": set_id, "threshold": threshold, "count": count, "number": number,
            "canonical": canonical}


def split_secret(helper, secret, threshold, count):
    if (threshold, count) not in POLICIES:
        raise ValueError("unsupported policy")
    raw = _run(helper, ["split", str(threshold), str(count)], secret)
    lines = [canonical_share(x.decode("ascii")) for x in raw.splitlines() if x.strip()]
    if len(lines) != count:
        raise RuntimeError("Secret helper returned the wrong share count")
    meta = [validate_share(helper, line) for line in lines]
    set_ids = {m["set_id"] for m in meta}
    if len(set_ids) != 1 or [(m["threshold"], m["count"], m["number"]) for m in meta] != [
        (threshold, count, i) for i in range(1, count + 1)
    ]:
        raise RuntimeError("Generated share metadata mismatch")
    return lines


def recover_secret(helper, shares):
    shares = [canonical_share(s) for s in shares]
    if not shares:
        raise ValueError("no shares")
    return _run(helper, ["recover"], ("\n".join(shares) + "\n").encode("ascii"))


def verify_every_combination(helper, shares, expected):
    meta = [validate_share(helper, s) for s in shares]
    first = meta[0]
    if any((m["set_id"], m["threshold"], m["count"]) !=
           (first["set_id"], first["threshold"], first["count"]) for m in meta):
        raise RuntimeError("Shares are not one consistent set")
    if len(shares) != first["count"]:
        raise RuntimeError("Share set is incomplete")
    checked = 0
    for combo in itertools.combinations(shares, first["threshold"]):
        if recover_secret(helper, combo) != expected:
            raise RuntimeError("A threshold share combination did not reconstruct the master secret")
        checked += 1
    return checked


def wipe_bytearray(value):
    for i in range(len(value)):
        value[i] = 0
