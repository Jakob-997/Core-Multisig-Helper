#!/usr/bin/env python3
"""Require distinct valid signatures from both pinned release signers."""
import pathlib
import sys

PINNED = {"D1DBF2C4B96F2DEBF4C16654410108112E7EA81F", "152812300785C96444D3334D17565732E08E5E41"}


def verify(text):
    valid = set()
    for line in text.splitlines():
        fields = line.split()
        if len(fields) < 2 or fields[0] != "[GNUPG:]":
            continue
        if fields[1] in {"BADSIG", "EXPSIG", "EXPKEYSIG", "REVKEYSIG", "NODATA"}:
            raise ValueError("Bad, expired, revoked or malformed signature input")
        if fields[1] == "FAILURE" and fields[2:] != ["gpg-exit", "33554433"]:
            raise ValueError("Unexpected GPG failure")
        if fields[1] == "VALIDSIG" and len(fields) >= 11:
            primary = fields[11] if len(fields) > 11 else fields[2]
            # SHA256/384/512 only.
            if fields[9] in {"8", "9", "10"}:
                valid.add(primary)
    if not PINNED <= valid:
        raise ValueError("Both pinned release signatures are required")


if __name__ == "__main__":
    verify(pathlib.Path(sys.argv[1]).read_text())
    print("Both pinned release signatures verified.")
