# Glacier-2 — experimental 3-of-7 offline wallet prototype

**Do not use meaningful funds until destructive recovery and spend tests pass.**
This is unaudited prototype software using Bitcoin Core **32.0rc2**, not a finished
Glacier security procedure. Default network: **regtest**, which has no real money.

Seven independent HD roots are generated on **one computer**. Compromise of that
computer can expose all seven keys. Multisig does not create independent security
domains here. Wallets, CDs, ISO images, and staging copies are **unencrypted**.
Any three signer backups plus the descriptor can spend. This produces Core wallet
backups, not BIP39 seed phrases. Protect all remaining local copies too.

## One copy-paste command

On a **dedicated disposable Ubuntu 24.04 or 26.04 installation**, at a local
console, with Internet initially available, `curl`, `tar`, and `sudo` installed,
an optical writer at `/dev/sr0`, and seven new blank CD-Rs:

```bash
bash -c 'set -euo pipefail; d=$(mktemp -d "$HOME/glacier2-source.XXXXXX"); curl --proto "=https" --tlsv1.2 -fsSL https://github.com/Jakob-997/Glacier-2/archive/refs/heads/main.tar.gz -o "$d/source.tar.gz"; tar -xzf "$d/source.tar.gz" -C "$d"; sudo bash "$d/Glacier-2-main/setup.sh"'
```

This downloads the repository before disabling networking; the local directory
is retained. It runs all four modules and pauses for destructive confirmations
and each disc. Inspect the source first when security matters. This convenience
command trusts the current GitHub branch, GitHub/TLS, Ubuntu packages and the host.
For reproducibility, download an independently reviewed commit archive instead.
Core binaries are separately checked against signed checksums.

To select another network or drive after downloading, run from that source folder:

```bash
sudo env GLACIER_CHAIN=signet GLACIER_DRIVE=/dev/sr0 bash setup.sh
```

`GLACIER_CHAIN=main` selects mainnet and requires an extra confirmation. Neither
mainnet nor signet setup synchronizes a blockchain. The offline node never needs
the chain to generate keys. Use a separate online watch-only coordinator later.
An existing `/var/lib/glacier2`, `/etc/glacier2`, or `/opt/glacier2` causes refusal.
Do not delete those directories to retry after keys may have been generated.

## Modules and outputs

| File | Responsibility |
| --- | --- |
| `setup.sh` | Local-console preflight, exclusive lock, ordered steps, completion records, cleanup |
| `lib/common.sh` | Logging, confirmations, dedicated Core lifecycle and RPC |
| `modules/install_core.sh` | Dependencies, pinned 32.0rc2 download, signatures/hash, isolated install |
| `modules/airgap.sh` | Persistent firewall, radio/service/driver blocks, interface unbinding and kernel module lock |
| `modules/wallets.sh`, `lib/wallets.py` | Seven blank signers, BIP87 account keys, private signer descriptors, watch-only policy, Core checks |
| `modules/backup_cd.sh` | `backupwallet`, one signer per CD, ISO creation, physical reinsertion/readback |

Core is installed under `/opt/glacier2/core`. State is root-only under
`/var/lib/glacier2`. The `public/` directory contains both checksummed receive and
change descriptors and a JSON manifest. Descriptors use
`wsh(sortedmulti(3,...))` with `m/87h/0h/0h/{0,1}/*` on mainnet or
`m/87h/1h/0h/{0,1}/*` on regtest/signet. Initial imported range: 0–999; extend it
when recovering addresses beyond that range. Seven roots are created by
`addhdkey`, account keys by `derivehdkey`. Each signer imports a descriptor with
only its own private account key; public outputs never include private keys.

Each disc contains exactly `wallet.dat` for that signer, `descriptors.txt`,
`manifest.json`, `RECOVERY.md`, `DISC.txt`, and `SHA256SUMS`. All seven public key
records are intentionally present on every disc: recovery needs the full policy.
Public descriptors are privacy-sensitive. Per-disc file hashes detect accidental
corruption, not malicious replacement of both data and hashes. Verification also
compares the readback image with the locally generated image.

## Verification trust

The installer requires valid SHA256-or-stronger signatures from **both** pinned
primary keys before checking the selected archive hash and extracting it:

* Hennadii Stepanov / hebasto: `D1DBF2C4B96F2DEBF4C16654410108112E7EA81F`
* Ava Chow / achow101: `152812300785C96444D3334D17565732E08E5E41`

Keys are fetched from the official `bitcoin-core/guix.sigs` repository but their
fingerprints are pinned here. Independently authenticate these trust anchors.
If either signer is missing, expired, revoked or invalid, stop; there is no bypass.
This is signature verification, not an independent reproducible build.

## Airgap behavior and limits

The runner disables swap, drops all non-loopback IPv4/IPv6 input/output/forwarding,
blocks radios, masks common network services, strips addresses and brings down
interfaces, unbinds discovered NICs, blacklists installed network/Bluetooth
drivers and sets boot parameters. It rebuilds initramfs/GRUB, installs early boot
enforcement and hotplug rules, and locks further kernel module loading until
reboot. Loopback stays available for cookie-authenticated Core RPC bound to
127.0.0.1 on dedicated port 18459. Core also starts with networking disabled.

**This is not a physical airgap or a defense against malicious root/kernel/firmware.**
Disable devices in firmware, physically remove Wi-Fi/Bluetooth hardware and
unplug Ethernet. Built-in drivers, already-loaded code, raw Layer-2 traffic,
early boot before enforcement, DMA, firmware radios and non-IP channels are not
eliminated by an inet firewall. Do not attach new USB devices after key creation.
Optical drivers are loaded before the module lock; some hardware may still need
additional drivers and will fail closed. Driver files are deliberately not deleted:
deletion does not stop built-in/loaded drivers and adds avoidable boot-repair risk.

Persistent files remain after failure. A later reboot must be tested for retained
isolation; it is not a license to reconnect. Never reconnect a machine that has
held these keys. Reinstall it only after verified recovery, with suitable media
sanitization. Live ISOs, WSL, containers, non-GRUB boot and remote operation are
unsupported production targets. Sleep/hibernate and firmware behavior require
separate hardware testing. This script does not claim secure erasure of RAM,
SSDs, swap history, temporary files, or optical discs.

## Reruns, failure and testing

Idempotence is deliberately **refuse-on-existing-state**, not silently generating
new wallets or repeating burns. An exclusive lock prevents concurrent runs.
Completion markers are audit hints, never sufficient evidence of safe state.
Failures stop subsequent stages, shut down the dedicated Core process and leave
network restrictions in place. No automatic wallet deletion, firewall rollback,
disc blanking, or regeneration occurs. Partial backup runs require manual review;
use existing wallets/backups and fresh media, never restart key creation.

Read [RECOVERY.md](RECOVERY.md) for the destructive test checklist.
Local, nondestructive code checks (with Bash, ShellCheck, Python, jq and xorriso):

```bash
shellcheck -x setup.sh lib/*.sh modules/*.sh
for f in setup.sh lib/*.sh modules/*.sh; do bash -n "$f"; done
python3 -m unittest discover -s tests -p 'test_*.py'
python3 tests/integration.py /path/to/verified/bitcoin-32.0rc2/bin
```

The integration test uses a disposable regtest directory, no airgap mutations and
no optical writes. It funds the watch wallet, restores seven `backupwallet` files
after ISO roundtrips, checks one signature per restored signer, rejects all 21
two-signer combinations and checks all 35 three-signer combinations with
`testmempoolaccept`. This does not replace actual CD, reboot or destructive recovery
tests. See [VALIDATION.md](VALIDATION.md) for results and outstanding hardware tests.

Primary references: [Core 32.0rc2 distribution](https://bitcoincore.org/bin/bitcoin-core-32.0/test.rc2/),
[Core verification guide](https://bitcoincore.org/en/download/),
[pinned multisig tutorial](https://github.com/bitcoin/bitcoin/blob/v32.0rc2/doc/multisig-tutorial.md),
[BIP87](https://github.com/bitcoin/bips/blob/master/bip-0087.mediawiki).
