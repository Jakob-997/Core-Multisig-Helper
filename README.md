# Core Multisig Helper

```text
   ██████╗ ██████╗ ██████╗ ███████╗
  ██╔════╝██╔═══██╗██╔══██╗██╔════╝
  ██║     ██║   ██║██████╔╝█████╗
  ██║     ██║   ██║██╔══██╗██╔══╝
  ╚██████╗╚██████╔╝██║  ██║███████╗
   ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝

       MULTISIG HELPER

      [◎]   [◎]   [◎]   [◎]
        \     |     |     /
             M-of-N
               |
            ₿ SPEND
```

A small Bitcoin Core helper for creating and using offline multisig wallets.

It is intentionally narrow, but it creates a real wallet you can use: generate the signer keys, burn the backups, create a watch-only wallet, and later load the signers to sign PSBTs.

This is **not a complete Bitcoin custody guide**. You still choose the M-of-N policy, physical storage, inheritance plan, and online wallet.

> **Status:** working testing draft, **not audited**. The multisig construction follows the WSH/BIP87 `sortedmulti` approach used by the Bitcoin Core multisig wizard work in PR #36325. Core wallet generation, backup/restore, watch-only, signing, PSBT finalization, and signer loading have been tested. Test the complete hardware workflow with disposable funds first.

## Security design

The goal is a small, understandable process built around Bitcoin Core rather than a new wallet stack.

- Bitcoin Core handles keys, descriptors, wallet backups and PSBT signing.
- Generation and signing use fresh Ubuntu Live sessions.
- Networking is disabled before private keys are generated or loaded.
- Swap is disabled; working wallet state lives in RAM-backed `/dev/shm`.
- Each signer is backed up to its own optical disc.
- Normal spending loads only one signer per fresh live session.
- A separate WATCH ONLY disc contains the public wallet and descriptor.

During initial generation, all N signer keys coexist on the one offline generation machine.

### Physical airgap strongly recommended

The script creates a software airgap, but malware or a sufficiently serious system compromise could theoretically defeat software controls.

For stronger assurance, use a machine with **no physical network path**. Remove the Wi-Fi/Bluetooth card if possible, remove any separate WWAN/cellular modem, and disconnect Ethernet or other network adapters.

Many laptops use one removable M.2 card for both Wi-Fi and Bluetooth. Some have soldered radios. If physical airgapping matters to you, use a laptop with removable radios or a desktop with no built-in wireless hardware.

### Signer discs are unencrypted

The signer discs contain an unencrypted Bitcoin Core `wallet.dat` and the public descriptor.

Anyone who gets one signer disc gets that signer's private key and can derive the wallet's addresses and monitor its on-chain activity. They **cannot spend** unless they obtain enough different signer backups to meet your M-of-N threshold.

This is the main tradeoff: weaker privacy and no at-rest encryption in exchange for a much simpler backup and recovery process with no extra passphrase or encryption secret to lose.

## Wallet layout

For an `M-of-N` wallet, Core Multisig Helper creates:

- **N private signer discs**
- **1 public WATCH ONLY disc**

Example: `2-4` means 2 different signers are required from 4 total signer backups, so you need **5 discs total**.

There are no seed words to transcribe.

## What you need

- Two USB drives:
  - **USB 1:** verified Ubuntu 26.04.1 x86-64 Desktop Live.
  - **USB 2:** Core Multisig Helper and, later, PSBT transfer.
- A CD/DVD writer/reader available as `/dev/sr0`.
- **N + 1 blank CD-Rs**.
- A permanent marker.
- An online Bitcoin wallet/node for creating PSBTs and broadcasting transactions.

## 1. Prepare the USBs

Download and verify Ubuntu 26.04.1 Desktop, then write it to **USB 1**.

Download and verify a Core Multisig Helper release, extract it, and copy the extracted `Core-Multisig-Helper` folder to **USB 2**.

Boot Ubuntu from USB 1 and use the live environment. **Do not install Ubuntu.**

## 2. Label the discs

Choose your M-of-N policy **before** generating the wallet, then label every blank disc before inserting any of them into the writer.

For a 2-of-4 wallet, prepare and label 5 discs:

```text
WATCH ONLY — 2-OF-4 — PUBLIC
SIGNER 1 OF 4 — 2-OF-4 — PRIVATE
SIGNER 2 OF 4 — 2-OF-4 — PRIVATE
SIGNER 3 OF 4 — 2-OF-4 — PRIVATE
SIGNER 4 OF 4 — 2-OF-4 — PRIVATE
```

Do this while the discs are still blank. Once generation starts, use the pre-labeled discs exactly when the script asks for them.

## 3. Generate the wallet

Insert USB 2, connect the optical writer, and have the pre-labeled discs ready.

Open a terminal and enter the project directory:

```bash
cd /path/to/Core-Multisig-Helper
sudo ./setup.sh
```

Choose:

```text
generate
```

Then enter your policy in `m-n` format, for example:

```text
2-4
```

There is no default.

Before generating keys the script disables swap and networking, then prints:

```text
AIRGAP ACTIVE — networking disabled before key generation.
```

It then creates the wallet in RAM.

## 4. Burn the backups

The script first writes the **WATCH ONLY** disc:

```text
watch_only.dat
descriptors.txt
```

It then writes one private signer disc for each signer:

```text
wallet.dat
descriptors.txt
```

Every disc is ejected, reinserted, and byte-compared against the ISO that was written. Do not treat a backup as complete until the script reports it verified.

The discs should already be labeled before generation. As each disc is written and verified, keep it with its matching label and store the private signer discs separately.

When generation is finished, **power the live computer off**.

## 5. Online wallet

Use the WATCH ONLY wallet to monitor the wallet, create PSBTs and broadcast completed transactions.

**Preferred:** your own Bitcoin Core node, optionally over Tor.

**Alternative:** Sparrow can create compatible PSBTs and can connect to your own node or a public Electrum server. If using a public server, Tor is recommended. A public Electrum server adds privacy and data-trust assumptions, so verify the transaction carefully on the offline signer before signing.

## 6. Sign a PSBT

Create the PSBT online and save it to **USB 2**.

Boot a **fresh Ubuntu Live session**, insert USB 2, enter the project directory and run:

```bash
cd /path/to/Core-Multisig-Helper
sudo ./setup.sh
```

Choose:

```text
spend
```

The script airgaps the machine, then asks for **one signer disc**. It copies that wallet into RAM, reads the M-of-N policy from the descriptor, and launches Bitcoin Core.

In Core:

1. Load the PSBT from USB 2.
2. Verify the destination, amount and fee.
3. Sign.
4. Save the partially signed PSBT back to USB 2.
5. Close Core and power the computer off.

Boot another fresh live session and repeat with a different signer disc until **M different signers** have signed.

For a 2-of-4 wallet, sign with any 2 different signer discs.

Then return USB 2 to the online computer and broadcast the completed transaction.

## Bitcoin Core

The repository currently includes frozen Bitcoin Core **32.0rc2 x86-64 Linux**.

SHA256:

```text
0255103718033e6aee15fa944717fc277e047b845bff1e7408af0ea732d8d0c1
```

The script verifies this before starting Core.

## Testing only

For development testing:

```bash
sudo apt install -y git && git clone --depth 1 https://github.com/Jakob-997/Core-Multisig-Helper.git && cd Core-Multisig-Helper && sudo ./setup.sh
```

Do not use a live clone of `main` for real funds. Use verified release artifacts.
