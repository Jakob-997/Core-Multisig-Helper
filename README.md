# Glacier-2 — experimental 3-of-7 offline wallet prototype

**Do not use meaningful funds until destructive recovery and spend tests pass.**
This is unaudited prototype software using Bitcoin Core **32.0rc2**, not a finished
Glacier security procedure. Default network: **Bitcoin mainnet**, creating real
Bitcoin receive addresses. Explicit regtest/signet options remain available for tests.

Seven independent HD roots are generated on **one computer**. Compromise of that
computer can expose all seven keys. Multisig does not create independent security
domains here. Wallets, CDs, ISO images, and staging copies are **unencrypted**.
Any three signer backups plus the descriptor can spend. This produces Core wallet
backups, not BIP39 seed phrases. Protect all remaining local copies too.

## One copy-paste command

On a **dedicated disposable Ubuntu 24.04 or 26.04 installation**, at a local
console in your logged-in GNOME desktop, with Internet initially available,
`curl`, `tar`, and `sudo` installed,
an optical writer at `/dev/sr0`, and seven new blank CD-Rs:

```bash
bash -c 'set -euo pipefail; d=$(mktemp -d "$HOME/glacier2-source.XXXXXX"); curl --proto "=https" --tlsv1.2 -fsSL https://github.com/Jakob-997/Glacier-2/archive/refs/heads/main.tar.gz -o "$d/source.tar.gz"; tar -xzf "$d/source.tar.gz" -C "$d"; sudo bash "$d/Glacier-2-main/setup.sh"'
```

This downloads the repository before disabling networking; the local directory
is retained. It runs all five modules with **no setup, hardening, mainnet or
identity confirmation prompts**. Only sudo authentication and the physical CD
burn/swap/readback prompts remain. Inspect the source first when security matters. This convenience
command trusts the current GitHub branch, GitHub/TLS, Ubuntu packages and the host.
For reproducibility, download an independently reviewed commit archive instead.
Core binaries are separately checked against signed checksums.

### Test without burning CDs

The same command with `--test` performs installation, real network hardening,
real mainnet wallet generation and desktop setup, but **skips the entire CD module
and all optical-device checks**. Test mode also places desktop copies of
`signer_1` through `signer_7` alongside `watch_only` and launches Bitcoin-Qt
with all eight wallets loaded so the generated signers can be inspected. No optical
drive is needed:

```bash
bash -c 'set -euo pipefail; d=$(mktemp -d "$HOME/glacier2-source.XXXXXX"); curl --proto "=https" --tlsv1.2 -fsSL https://github.com/Jakob-997/Glacier-2/archive/refs/heads/main.tar.gz -o "$d/source.tar.gz"; tar -xzf "$d/source.tar.gz" -C "$d"; sudo bash "$d/Glacier-2-main/setup.sh" --test'
```

From an already downloaded source directory: `sudo bash setup.sh --test`.
**This is not a dry run, does not select a test network, and leaves you without
CD recovery media.** It disables networking persistently and creates real keys.
In test mode the seven signer wallet copies are deliberately accessible to the
logged-in desktop account for Bitcoin-Qt inspection. **Do not fund this test setup.**
Existing-state checks still prevent rerunning over the same keys. Test-network
selection remains a separate `GLACIER_CHAIN` option.

To select another network or drive after downloading, run from that source folder:

```bash
sudo env GLACIER_CHAIN=regtest GLACIER_DRIVE=/dev/sr0 bash setup.sh
```

Mainnet is already selected unless overridden; no extra confirmation is requested. Neither
mainnet nor signet setup synchronizes a blockchain. The offline node never needs
the chain to generate keys. Use a separate online watch-only coordinator later.
An existing `/var/lib/glacier2`, `/etc/glacier2`, or `/opt/glacier2` causes refusal.
Do not delete those directories to retry after keys may have been generated.

## Modules and outputs

| File | Responsibility |
| --- | --- |
| `setup.sh`, `lib/options.sh` | Local preflight, `--test` routing, exclusive lock, ordered steps, completion records, cleanup |
| `lib/common.sh` | Logging, disc confirmations, dedicated Core lifecycle and RPC |
| `modules/install_core.sh` | Dependencies, pinned 32.0rc2 download, signatures/hash, isolated install |
| `modules/airgap.sh` | Persistent firewall, radio/service/driver blocks, interface unbinding and kernel module lock |
| `modules/wallets.sh`, `lib/wallets.py` | Seven blank signers, BIP87 account keys, private signer descriptors, watch-only policy, Core checks |
| `modules/desktop_identity.sh`, `lib/desktop_identity.py` | Recognition wallpaper/color/code, GNOME settings, offline Core Qt shortcut |
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
`manifest.json`, `identity.json`, `RECOVERY.md`, `DISC.txt`, and `SHA256SUMS`. All seven public key
records are intentionally present on every disc: recovery needs the full policy.
Public descriptors are privacy-sensitive. Per-disc file hashes detect accidental
corruption, not malicious replacement of both data and hashes. Verification also
compares the readback image with the locally generated image.

## Desktop identity and Bitcoin Core Qt

After wallet creation, the desktop module generates an 80-bit random recognition
code and a random dark background color locally with the operating system's
cryptographic random generator. The wallpaper says **OFFLINE LAPTOP / COLD STORAGE**,
shows the network, code, and color value, and asks you to compare them with a
separate paper record. The identity is saved once under `/opt/glacier2/identity`
and copied to every backup CD. Reruns never silently replace it.

This is a visual anti-phishing cue, **not an anti-exfiltration mechanism or proof
that the computer/software has not changed**. Malware can copy the image and code.
Compare against your paper record, not another file on the same laptop. A mismatch
means stop and investigate; a match does not establish trust.

The module sets GNOME light/dark desktop wallpaper and the legacy lock wallpaper
key where available. Modern GNOME uses a **blurred desktop image on the lock
screen**, often hiding the code/text. Check both desktop and lock/unlock manually;
the script does not remove lock-screen blur, install shell extensions, change the
login screen, or claim the code is readable while locked. It records previous
changed settings in `~/.local/share/glacier2/desktop-settings.json`.

An Applications launcher named **Bitcoin Core — Offline Watch Wallet** is added,
with a desktop copy where a Desktop folder exists and GNOME favorites pinning
where allowed. Some desktops require right-click **Allow Launching**. The shortcut
uses the [official Bitcoin Core Qt SVG icon](https://github.com/bitcoin/bitcoin/blob/v32.0rc2/src/qt/res/src/bitcoin.svg),
bundled unchanged with its upstream license; there is no generated substitute.
The shortcut starts the verified `bitcoin-qt` with networking disabled and a
separate user-owned Core datadir at `~/.local/share/glacier2/core`. In a normal
run that datadir contains only the **watch-only** wallet; Qt does not run as root
and the seven signer wallets are not exposed to the desktop account. In `--test`
mode, the same datadir additionally contains desktop copies of all seven signer
wallets and the launcher loads all eight wallets for inspection. The normal
watch-only launcher can display/generate real mainnet addresses, but cannot sign. Since it stays
offline it does not provide synchronized balances. Do not open it until setup
has finished, and never reconnect this computer. Existing installations still
require manual review; do not rerun setup to retrofit these cues over existing keys.

References: [GNOME desktop background](https://help.gnome.org/system-admin-guide/desktop-background.html),
[legacy lock-screen setting](https://help.gnome.org/system-admin-guide/desktop-shield.html),
[modern GNOME lock background behavior](https://mail.gnome.org/archives/commits-list/2020-February/msg11612.html).

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
drivers, plus installed NFC/UWB and selected radio/SDR driver families, and sets
boot parameters. It rebuilds initramfs/GRUB and installs boot enforcement and
hotplug rules. Each boot reapplies the firewall/radio/link restrictions and locks
further kernel module loading. Boot-enforcement failure requests emergency-mode
isolation; that failure path still needs a physical-machine test. Loopback stays
available for cookie-authenticated Core RPC bound to
127.0.0.1 on dedicated port 18459. Core also starts with networking disabled.

**Persistent does not mean irreversible or universal.** The kernel's
`modules_disabled=1` lock cannot be reset within that running kernel. A reboot
starts a new kernel, so the enabled service reapplies the lock; it does not erase
the saved firewall, driver blacklist, masked services or boot parameters.
Root can still alter those saved rules, use already-loaded drivers, or boot another
OS. See the [kernel module-lock documentation](https://docs.kernel.org/admin-guide/sysctl/kernel.html#modules-disabled).

**This is not a physical airgap or a defense against malicious root/kernel/firmware.**
Disable devices in firmware, physically remove Wi-Fi/Bluetooth hardware and
unplug Ethernet. Also remove/disconnect cellular/WWAN modems, USB tethering/network
adapters, NFC/UWB devices, external radios and SDR hardware. `rfkill block all`
covers radios registered with Linux rfkill, not every transmitter that could exist;
software blocks are reversible ([kernel rfkill documentation](https://docs.kernel.org/driver-api/rfkill.html)).
Some radios are accessible directly from user space, without a network driver.
An antenna alone is not a transmitter; the attached radio hardware must be removed
or disabled physically. No script can certify “any possible escape,” including
firmware or acoustic/optical/electromagnetic side channels.
Built-in drivers, already-loaded code, raw Layer-2 traffic,
early boot before enforcement, DMA, firmware radios and non-IP channels are not
eliminated by an inet firewall. Do not attach new USB devices after key creation.
In normal mode optical drivers are loaded before the module lock; `--test` skips
them, including on subsequent boots. Some hardware may still need
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
Local, nondestructive code checks (with Bash, ShellCheck, Python/Pillow,
DejaVu fonts, jq and xorriso):

```bash
bash tests/check.sh
python3 tests/integration.py /path/to/verified/bitcoin-32.0rc2/bin
python3 tests/mainnet_qt.py /path/to/verified/bitcoin-32.0rc2/bin
```

The integration test uses a disposable regtest directory, no airgap mutations and
no optical writes. It funds the watch wallet, restores seven `backupwallet` files
after ISO roundtrips, checks one signature per restored signer, rejects all 21
two-signer combinations and checks all 35 three-signer combinations with
`testmempoolaccept`. This does not replace actual CD, reboot or destructive recovery
tests. See [VALIDATION.md](VALIDATION.md) for results and outstanding hardware tests.
The mainnet Qt smoke test uses temporary wallets with networking disabled and no funds.

Primary references: [Core 32.0rc2 distribution](https://bitcoincore.org/bin/bitcoin-core-32.0/test.rc2/),
[Core verification guide](https://bitcoincore.org/en/download/),
[pinned multisig tutorial](https://github.com/bitcoin/bitcoin/blob/v32.0rc2/doc/multisig-tutorial.md),
[BIP87](https://github.com/bitcoin/bips/blob/master/bip-0087.mediawiki).
