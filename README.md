# Glacier-2

**A minimal 3-of-7 Bitcoin cold-storage appliance built around Bitcoin Core.**

Glacier-2 turns a clean Ubuntu computer into a permanently offline Bitcoin signing
machine. It creates seven independent Bitcoin Core signer wallets, a 3-of-7
`wsh(sortedmulti(...))` policy, a desktop watch-only wallet, and seven verified
CD-R backups — one private signer per disc.

> [!WARNING]
> **Glacier-2 is experimental, unaudited prototype software. Do not use meaningful
> funds until you have completed the full recovery and spend test in
> [RECOVERY.md](RECOVERY.md).**

## What you end up with

| Item | Purpose |
| --- | --- |
| Offline Ubuntu computer | Generates and holds the original signer wallets |
| Bitcoin Core watch-only wallet | Displays and derives addresses without needing private keys |
| Signer 1 through Signer 7 CD-Rs | One private Bitcoin Core wallet backup per disc |
| Public descriptor / manifest | Defines the complete 3-of-7 wallet policy |
| Recognition code + color | A visual cue for recognizing the dedicated offline machine |

Glacier-2 uses Bitcoin Core wallet backups, **not BIP39 seed words**. Any three
different signer backups, together with the public wallet policy, are sufficient
to spend.

---

# Setup instructions

## 1. Prepare the computer

Use a computer dedicated to Glacier-2. A spare laptop is ideal.

You need:

- Ubuntu Desktop **24.04 or 26.04**
- one internal drive **or** a separate USB SSD/flash drive to install Ubuntu onto
- the Ubuntu installer USB
- a USB or internal CD/DVD writer
- **seven new blank CD-R discs**
- Internet access only for the initial Ubuntu/Core installation
- a pen or permanent marker for labeling the discs and recording the recognition code

For a serious setup, start from an official Ubuntu image and verify it before use.
Do not use an everyday computer that already contains sensitive data.

## 2. Install a clean Ubuntu system

Boot the Ubuntu installer and proceed through the normal installation.

At **Disk setup**:

1. Choose **Erase disk and install Ubuntu**.
2. Select the drive that will become the Glacier-2 system. This can be the
   computer's internal drive or a dedicated second USB drive. Do **not** erase the
   Ubuntu installer USB by mistake.
3. Enable full-disk encryption.

### Encryption option A — TPM-backed encryption

If Ubuntu offers **Use hardware-backed disk encryption**, you can use the machine's
TPM to protect the installation at rest.

Ubuntu currently describes TPM-backed FDE as experimental on 24.04 and Beta on
26.04. Store the recovery key outside the Glacier computer. For a security-sensitive
cold-storage machine, adding a disk PIN or passphrase provides additional protection.

Ubuntu documentation:

- [Ubuntu TPM-backed disk encryption](https://ubuntu.com/desktop/docs/en/latest/explanation/hardware-backed-disk-encryption/)
- [Enable TPM encryption during installation](https://ubuntu.com/desktop/docs/en/latest/how-to/encrypt-your-disk-with-tpm/)

### Encryption option B — normal encrypted install

If TPM-backed encryption is unavailable or you prefer conventional passphrase
protection, use Ubuntu's normal encrypted-disk option and choose a strong,
unique passphrase.

If you want a simple machine-generated value, open a terminal in the live Ubuntu
environment and run:

```bash
uuidgen -r
```

If `uuidgen` is unavailable:

```bash
systemd-id128 new
```

Write the value down carefully and keep it somewhere physically separate from the
computer. Losing the disk-encryption secret can make the installation unrecoverable.

Finish the Ubuntu installation, reboot into the newly installed system, and log in.

## 3. Prepare the backup media

Before running Glacier-2:

1. Plug in the CD/DVD writer.
2. Keep the writer connected for the entire setup.
3. Have seven blank **CD-R** discs ready.
4. Label them:

```text
Glacier-2 — Signer 1 of 7
Glacier-2 — Signer 2 of 7
Glacier-2 — Signer 3 of 7
Glacier-2 — Signer 4 of 7
Glacier-2 — Signer 5 of 7
Glacier-2 — Signer 6 of 7
Glacier-2 — Signer 7 of 7
```

Do not use CD-RW media.

> [!IMPORTANT]
> Connect the optical writer **before** Glacier-2 hardens the machine. Do not attach
> new USB devices after key generation begins.

The seven discs are all **private signer backups**. There is not a private
"watch-only disc." Public/watch-only recovery information is included on every
signer disc.

If you want a separate eighth medium labeled **GLACIER-2 — PUBLIC / WATCH ONLY**,
make it later on a separate clean computer using only the public files
(`descriptors.txt`, `manifest.json`, `identity.json`, and `RECOVERY.md`).
Never copy `wallet.dat` onto public media.

## 4. Run Glacier-2

The computer must still have Internet access at this point.

Copy and paste this entire command into Terminal:

```bash
bash -c 'set -euo pipefail; if ! command -v curl >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y --no-install-recommends ca-certificates curl; fi; d=$(mktemp -d "$HOME/glacier2-source.XXXXXX"); curl --proto "=https" --tlsv1.2 -fsSL https://github.com/Jakob-997/Glacier-2/archive/refs/heads/main.tar.gz -o "$d/source.tar.gz"; tar -xzf "$d/source.tar.gz" -C "$d"; sudo bash "$d/Glacier-2-main/setup.sh"'
```

Enter your Ubuntu password when `sudo` asks for it.

Glacier-2 will:

1. install the required packages and verified Bitcoin Core build;
2. harden the machine and disable networking;
3. create seven independent signer wallets;
4. build and validate the 3-of-7 descriptor wallet;
5. create the offline desktop/watch-only Bitcoin Core launcher;
6. ask for each CD-R in order;
7. burn the corresponding signer wallet;
8. eject it and require a physical reinsertion/readback verification before continuing.

Once the hardening stage begins, **do not reconnect the machine to a network**.

> [!NOTE]
> The convenience command above downloads the current `main` branch. For a
> high-assurance setup, review the source first and use a specific reviewed commit
> instead of trusting a moving branch.

## 5. Follow the CD prompts

When Glacier-2 asks for a disc, insert the matching blank disc.

For example:

```text
BURN SIGNER 1  -> insert "Glacier-2 — Signer 1 of 7"
BURN SIGNER 2  -> insert "Glacier-2 — Signer 2 of 7"
...
BURN SIGNER 7  -> insert "Glacier-2 — Signer 7 of 7"
```

The program burns the disc, ejects it, asks you to reinsert it, and verifies the
readback before moving to the next signer.

Do not mix up the labels.

## 6. Record the machine identity

Glacier-2 gives the offline desktop a randomly generated recognition color and code.

Write both down on paper and keep that record separately from the laptop.

The recognition cue is useful for spotting an obviously different environment, but
it is **not cryptographic attestation**. Malware could copy the wallpaper and code.

## 7. After setup

When setup finishes:

- keep the Glacier computer permanently offline;
- do not reconnect Ethernet, Wi-Fi, Bluetooth, cellular, tethering, or other radios;
- do not attach new USB devices unless your recovery procedure specifically requires it;
- store the seven signer discs in separate protected locations;
- protect the public descriptor too — it cannot spend coins, but it reveals your wallet structure and addresses;
- open **Bitcoin Core — Offline Watch Wallet** only on the offline machine;
- remember that the offline watch wallet cannot synchronize balances;
- complete the recovery test before sending meaningful funds.

Read **[RECOVERY.md](RECOVERY.md)** before treating the wallet as usable.

---

## Test the project without burning CDs

For development only, append `--test`:

```bash
bash -c 'set -euo pipefail; if ! command -v curl >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y --no-install-recommends ca-certificates curl; fi; d=$(mktemp -d "$HOME/glacier2-source.XXXXXX"); curl --proto "=https" --tlsv1.2 -fsSL https://github.com/Jakob-997/Glacier-2/archive/refs/heads/main.tar.gz -o "$d/source.tar.gz"; tar -xzf "$d/source.tar.gz" -C "$d"; sudo bash "$d/Glacier-2-main/setup.sh" --test'
```

`--test` is **not a dry run**. It performs real hardening and creates real keys,
but skips the CD module. For inspection, Bitcoin-Qt loads:

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

The signer wallets are deliberately exposed to the desktop account in test mode.
**Never fund a `--test` installation.**

For regtest instead of mainnet:

```bash
sudo env GLACIER_CHAIN=regtest bash setup.sh --test
```

---

## Storage model

A 3-of-7 wallet remains spendable if you retain any three valid signer backups,
but the goal is not merely to have three surviving discs. Keep all seven healthy,
geographically separated where practical, and periodically verify readability.

Each signer CD contains:

- that signer's private `wallet.dat`;
- the complete public descriptors;
- `manifest.json`;
- the recognition identity;
- recovery instructions;
- checksums.

The CD itself is **not encrypted**. Physical custody is the security boundary.

## Important limitations

- All seven keys are initially generated on the same computer. A compromise during
  generation can therefore compromise the whole multisig.
- The software airgap is defense in depth, not a substitute for physically removing
  or disabling network/radio hardware.
- Glacier-2 does not provide secure erase.
- Glacier-2 does not use hardware wallets or seven independent signing devices.
- Glacier-2 is not formally audited.
- Passing automated tests does not prove the physical procedure is safe.

For the implementation details and threat-model discussion, see
**[TECHNICAL.md](TECHNICAL.md)**.

## Documentation

- **[RECOVERY.md](RECOVERY.md)** — destructive recovery and spend-test procedure
- **[TECHNICAL.md](TECHNICAL.md)** — architecture, wallet policy, airgap design, verification, and failure behavior
- **[VALIDATION.md](VALIDATION.md)** — tests completed so far and outstanding physical tests

## Project status

Glacier-2 currently targets Ubuntu 24.04/26.04 and Bitcoin Core 32.0rc2. It is an
experimental attempt to make a small, understandable Bitcoin Core cold-storage
procedure rather than a general-purpose wallet.
