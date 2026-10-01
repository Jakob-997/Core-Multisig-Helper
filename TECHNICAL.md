# Glacier-2 technical reference

This document contains implementation details, security assumptions, and testing
information that would otherwise make the main [README](README.md) difficult to
follow.

> [!WARNING]
> Glacier-2 is experimental and unaudited. This document describes the current
> implementation; it is not a claim that the design is secure enough for meaningful
> funds.

## Architecture

Glacier-2 deliberately keeps the execution path shallow. `setup.sh` contains the
complete ordered setup procedure as five plainly named stages:

1. `install_core`
2. `airgap`
3. `wallets`
4. `desktop_identity`
5. `backup_cd`

There is no module loader and no per-stage wrapper file. A reviewer can follow the
privileged setup path from top to bottom in one script.

| File | Responsibility |
| --- | --- |
| `setup.sh` | preflight, Core lifecycle, verified install, airgap, stage ordering, desktop handoff, CD backup, cleanup |
| `lib/wallets.py` | 3-of-7 BIP87 signer/watch-wallet construction and validation |
| `lib/desktop_identity.py` | recognition wallpaper/code and GNOME watch-wallet integration |
| `lib/enforce-airgap.sh` | boot/runtime enforcement and verification of the installed airgap |
| `lib/verify_signatures.py` | strict checking of the two pinned Bitcoin Core release signatures |
| `lib/launch-qt.sh` | tiny unprivileged launcher for the offline Bitcoin-Qt desktop copy |

The separate helpers remain only where they have an independent runtime or a
security-sensitive unit-test boundary. Declarative nftables and systemd files remain
under `config/` rather than being hidden inside shell strings.

Bitcoin Core is installed under:

```text
/opt/glacier2/core
```

Root-owned Glacier state is kept under:

```text
/var/lib/glacier2
```

The normal desktop watch-only Core datadir is separate:

```text
~/.local/share/glacier2/core
```

This separation is intentional. Production mode gives the desktop user only the
watch-only wallet. `--test` deliberately adds copies of all seven signer wallets
to that desktop datadir so they can be inspected in Bitcoin-Qt.

## Wallet construction

The current policy is fixed at **3-of-7**.

Seven blank descriptor wallets are created with Bitcoin Core. Each receives one
independent HD root using `addhdkey`.

The BIP87 account path is:

```text
mainnet:        m/87h/0h/0h
regtest/signet: m/87h/1h/0h
```

The receive and change policies are:

```text
wsh(sortedmulti(3, KEY1/0/*, KEY2/0/*, ... KEY7/0/*))
wsh(sortedmulti(3, KEY1/1/*, KEY2/1/*, ... KEY7/1/*))
```

Each signer imports the complete policy, but only its own account key is private.
The watch wallet imports the same policy with no private keys.

The initial imported range is 0–999. Recovery procedures must extend the range if
addresses beyond that index have been used.

The wallet generator validates:

- seven distinct roots/account xpubs;
- descriptor checksums and solvability;
- private-key presence only where expected;
- identical active public descriptors across every signer and watch wallet;
- sample receive/change addresses across all eight wallets.

## Public outputs

The root-owned `public/` state contains:

- `manifest.json`
- `descriptors.txt`
- `identity.json` after desktop setup

The manifest records the network, threshold, signer count, BIP87 account path,
public key records, descriptors, initial range, and sample addresses.

Public descriptors cannot directly spend, but they are **privacy-sensitive**:
they reveal the complete wallet policy and allow addresses to be derived.

## Signer CD format

Each of the seven signer discs contains exactly one private Core wallet backup plus
the complete public recovery policy:

```text
wallet.dat
manifest.json
descriptors.txt
identity.json
RECOVERY.md
DISC.txt
SHA256SUMS
```

Every signer disc contains all seven public key records because recovery of a
multisig wallet requires the complete policy.

The program:

1. creates a signer-specific staging directory;
2. runs Core `backupwallet`;
3. builds a read-only ISO;
4. verifies the target medium is blank CD-R;
5. burns with xorriso/cdrecord;
6. ejects the disc;
7. requires physical reinsertion;
8. reads the written sectors back;
9. compares the readback ISO byte-for-byte;
10. extracts the readback and verifies `SHA256SUMS`;
11. compares the restored `wallet.dat` with the staged original.

Checksums detect accidental corruption. They do not authenticate against an attacker
who can replace both the data and the checksums.

## Desktop identity and Bitcoin-Qt

The desktop module creates an 80-bit random recognition token and a random dark
background color using the operating system CSPRNG.

The wallpaper displays:

- `OFFLINE LAPTOP`
- `COLD STORAGE`
- the Bitcoin network
- the recognition code
- the color value
- a reminder to keep the machine offline

The identity is created once and copied to every backup disc. Existing identity
state is not silently regenerated.

This is a **recognition cue only**. It is not remote attestation and does not prove
that the operating system or software has not been modified. Malware could reproduce
the same wallpaper.

In production mode the launcher opens only:

```text
watch_only
```

In `--test` mode it opens:

```text
watch_only
signer_1
signer_2
signer_3
signer_4
signer_5
signer_6
signer_7
```

The normal watch-only desktop wallet can derive addresses but cannot sign. Because
the signing computer stays offline, it is not a synchronized balance-monitoring
wallet.

## Bitcoin Core verification

The installer currently targets Bitcoin Core **32.0rc2**.

It downloads the archive, `SHA256SUMS`, and `SHA256SUMS.asc` from the official
Bitcoin Core distribution location.

The installer requires valid SHA256-or-stronger signatures from both pinned primary
fingerprints:

- Hennadii Stepanov / hebasto:
  `D1DBF2C4B96F2DEBF4C16654410108112E7EA81F`
- Ava Chow / achow101:
  `152812300785C96444D3334D17565732E08E5E41`

Builder keys are fetched from the official `bitcoin-core/guix.sigs` repository,
their full fingerprints are checked, and the selected archive hash is verified
before extraction.

This is signature/checksum verification. It is **not** an independent reproducible
build of Bitcoin Core.

## Airgap behavior

The hardening module attempts to reduce the ways the signer can reconnect by:

- disabling swap;
- installing an nftables policy that drops non-loopback IPv4/IPv6 traffic;
- blocking registered radios with rfkill;
- masking common network services;
- removing interface addresses and routes;
- bringing non-loopback interfaces down;
- unbinding discovered network devices;
- blacklisting installed network/Bluetooth drivers and selected other radio families;
- adding persistent boot parameters and service enforcement;
- rebuilding initramfs/GRUB;
- applying a kernel module-loading lock during the generation session.

Bitcoin Core is also started with:

- `networkactive=0`
- `listen=0`
- `discover=0`
- `dnsseed=0`
- `fixedseeds=0`
- `listenonion=0`
- `natpmp=0`

Loopback remains available for local cookie-authenticated RPC on the dedicated
Glacier port.

### Limits of the software airgap

Software isolation is defense in depth, **not a physical airgap**.

It does not prove protection against:

- malicious root/kernel/firmware;
- already-loaded or built-in drivers;
- DMA-capable devices;
- alternate operating systems;
- firmware-controlled radios;
- raw or non-IP communication channels;
- cellular/WWAN hardware not controlled as a normal Linux network interface;
- NFC/UWB/SDR hardware;
- acoustic, optical, electromagnetic, or other exotic side channels.

For serious use, physically remove or disable Wi-Fi/Bluetooth/radio hardware,
unplug Ethernet, and do not attach new USB devices after key generation.

The kernel `modules_disabled=1` lock applies only to the running kernel. A reboot
starts a new kernel; the persistent Glacier service is responsible for reapplying
the restrictions.

## Full-disk encryption

Glacier-2 does not configure the Ubuntu system drive itself; disk encryption is
selected during the Ubuntu installation.

Ubuntu 24.04 describes hardware-backed TPM disk encryption as experimental.
Ubuntu 26.04 describes it as Beta. On supported machines it stores automatically
generated disk-encryption keys in the TPM and checks measured boot state before
unlocking.

For a cold-storage laptop, an additional disk PIN or passphrase can protect against
some attacks that possession of the whole computer or compromise of the TPM would
otherwise make easier.

Traditional passphrase-based full-disk encryption remains a valid alternative.

Disk encryption protects the installed drive **at rest**. It does not protect
wallet material from malware executing after the disk is unlocked.

## Rerun and failure behavior

Glacier-2 intentionally refuses to regenerate over existing state.

If any of the protected state paths already exist, setup stops rather than silently
creating a new wallet.

An exclusive `flock` prevents concurrent runners.

On failure:

- later stages stop;
- the dedicated Core process is shut down;
- applied airgap restrictions are left in place;
- wallet state is preserved;
- existing discs/staging are not automatically erased or regenerated.

Completion marker files are useful audit hints but are not proof that the wallet or
backup media are valid.

A partial backup run requires manual review. Do not delete wallet state and restart
key generation simply to obtain a clean run.

## Testing

Local static/unit checks:

```bash
bash tests/check.sh
```

Real-Core regtest integration:

```bash
python3 tests/integration.py /path/to/verified/bitcoin-32.0rc2/bin
```

Mainnet/Qt smoke test:

```bash
python3 tests/mainnet_qt.py /path/to/verified/bitcoin-32.0rc2/bin
```

The integration test creates disposable regtest wallets, restores signer backups,
checks signer behavior, verifies that all 21 two-signer combinations remain
incomplete, and checks that all 35 three-signer combinations can finalize and pass
`testmempoolaccept`.

These tests do not replace:

- physical CD-R burn/readback tests;
- physical Ubuntu install tests;
- reboot/sleep/hotplug isolation tests;
- destructive recovery from only the backup media;
- independent security review.

See [VALIDATION.md](VALIDATION.md) for the current validation record and
[RECOVERY.md](RECOVERY.md) for the acceptance procedure.

## Primary references

- [Bitcoin Core 32.0rc2 distribution](https://bitcoincore.org/bin/bitcoin-core-32.0/test.rc2/)
- [Bitcoin Core verification guide](https://bitcoincore.org/en/download/)
- [Bitcoin Core multisig tutorial](https://github.com/bitcoin/bitcoin/blob/v32.0rc2/doc/multisig-tutorial.md)
- [BIP87](https://github.com/bitcoin/bips/blob/master/bip-0087.mediawiki)
- [Ubuntu hardware-backed disk encryption](https://ubuntu.com/desktop/docs/en/latest/explanation/hardware-backed-disk-encryption/)
- [Linux kernel module-lock documentation](https://docs.kernel.org/admin-guide/sysctl/kernel.html#modules-disabled)
- [Linux rfkill documentation](https://docs.kernel.org/driver-api/rfkill.html)
