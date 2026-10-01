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

### Audit status

This is **unaudited software**. AI-assisted review and automated testing have been used extensively to check the code and verify that it does what it is intended to do, but that is not a substitute for an independent expert audit.

Versioned releases are planned soon so an auditor can review a specific immutable version. An easy way to help is to take a release to a Bitcoin security expert and ask them to verify that it correctly and safely creates, backs up, restores, and signs with the intended Bitcoin Core multisig wallet.

This project is open-source public utility software. Independent review is welcome. If you are qualified and would like to help audit it, please get in touch. If additional motivation is needed, a community audit bounty can be raised, and anyone is free to organize fundraising to support an independent audit. The project is intentionally small, so a focused audit should be relatively limited in scope.

### Bitcoin Core reference implementation

This project used Bitcoin Core [issue #35645 — Multisig Wizard tracking issue](https://github.com/bitcoin/bitcoin/issues/35645), [PR #36325 — Contrib: add multisig wizard](https://github.com/bitcoin/bitcoin/pull/36325), and its [`contrib/multisig/wizard.py`](https://github.com/bitcoin/bitcoin/blob/2803e1518bb22394a80bac94e2435bb3982d0cde/contrib/multisig/wizard.py) implementation as important references for the multisig construction and Bitcoin Core RPC flow.

The upstream wizard uses the same BIP 87 account path and `wsh(sortedmulti(...))` multipath descriptor construction used here. If and when that work is officially merged into Bitcoin Core, a future version of Core Multisig Helper can consider directly adapting the upstream implementation instead of maintaining duplicate wallet-construction logic.

You can also help by reviewing, testing, and helping move the upstream Python multisig wizard and broader Bitcoin Core multisig GUI work toward merge. Ideally, this helper would eventually become unnecessary because the same workflow would live directly in Bitcoin Core, where it could benefit from the review process, testing, maintenance, and trust model of the Bitcoin Core repository itself.

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

Every CD includes the wallet's **public descriptor**. That descriptor contains all cosigner xpub information needed to derive the wallet's receive and change addresses. Anyone who gets access to **any** CD — including the WATCH ONLY disc — can derive the wallet's addresses and monitor its on-chain activity. In practical terms, access to any one CD means losing the wallet's address privacy.

Each signer disc additionally contains an unencrypted Bitcoin Core `wallet.dat` holding that signer's private key. Anyone who gets one signer disc therefore gets **one of the M-of-N signing keys plus the full public descriptor**. They still cannot spend unless they obtain enough different signer backups to satisfy the M-of-N threshold.

This is the main tradeoff: the CDs provide no at-rest encryption or descriptor privacy, in exchange for a much simpler backup and recovery process with no additional passphrase or encryption secret to lose.

## Wallet layout

For an `M-of-N` wallet, Core Multisig Helper creates:

- **N private signer discs**
- **1 public WATCH ONLY disc**

Example: `2-4` means 2 different signers are required from 4 total signer backups, so you need **5 discs total**.

There are no seed words to transcribe.

## What you need

- A **64-bit x86-64 capable laptop or desktop**. A laptop is the expected setup; if you want a physical airgap, prefer one with removable Wi-Fi/Bluetooth hardware.
- Two USB drives:
  - **USB 1:** verified Ubuntu 26.04.1 x86-64 Desktop Live.
  - **USB 2:** the verified Core Multisig Helper release and, later, PSBT transfer.
- A CD/DVD writer/reader available as `/dev/sr0`.
- **N + 1 blank CD-Rs**.
- A permanent marker.
- An online Bitcoin wallet/node for creating PSBTs and broadcasting transactions.

## 1. Prepare the USBs

Download and verify Ubuntu 26.04.1 Desktop, then write it to **USB 1**.

Download a Core Multisig Helper release, verify it against the independently obtained published release hash/signature, extract it, and copy the extracted `Core-Multisig-Helper` folder to **USB 2**. Verify it again from the Ubuntu Live session before first use.

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

Open a terminal, navigate to the Core Multisig Helper project directory, then run:

```bash
sudo bash setup.sh
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

Treat the **online computer as untrusted**. Its job is to monitor the wallet, construct PSBTs and broadcast transactions—not to tell you what is safe to sign.

**Preferred:** your own Bitcoin Core node, optionally over Tor. This keeps the online wallet stack centered on Bitcoin Core.

**Alternative:** Sparrow is convenient if you mainly want to view the wallet and construct PSBTs without running your own fully synced node. It can connect to your own node or a public Electrum server; use Tor with a public server. Sparrow adds another wallet codebase and review surface, so a bad or compromised change has another opportunity to mislead the online view.

Whichever online wallet you use, follow these rules:

- **Never trust an online-generated receive address by itself.** To receive funds, boot a fresh offline Ubuntu session, load one of your authentic signer CDs in `spend` mode, and use or verify the address shown by that offline signer.
- **Before signing a spend, verify the destination, amount, fee and every change output on the offline signer.** Confirm that each change output belongs to your multisig wallet.
- Assume the online computer may be lying to you. **Only trust addresses derived and displayed by the fresh live-booted offline laptop with one of your authentic Core Multisig Helper discs loaded.** Do not treat an address shown only by the online wallet as authoritative.

## 6. Sign a PSBT

Create the PSBT online and save it to **USB 2**.

> **Security warning:** Understand that the PSBT USB transfers data between the online and offline computers. If that USB is compromised, it becomes a security risk to the offline signing environment. Treat transfer media as untrusted.

Boot a **fresh Ubuntu Live session** and insert USB 2 containing Core Multisig Helper and the PSBT. Navigate to the Core Multisig Helper project directory and run:

```bash
sudo bash setup.sh
```

Choose:

```text
spend
```

The script airgaps the machine, then asks you to insert and mount **one signer disc**. It copies that wallet into RAM, reads the M-of-N policy from the descriptor, and launches Bitcoin Core.

In Core:

1. Load the PSBT from USB 2.
2. Verify the destination, amount, fee and **all change outputs**.
3. Confirm every change output belongs to your multisig wallet.
4. Sign.
5. Save the partially signed PSBT back to USB 2.
6. Close Core and power the computer off.

Boot another fresh live session and repeat with a different signer disc until **M different signers** have signed.

For a 2-of-4 wallet, sign with any 2 different signer discs.

Then return USB 2 to the online computer and broadcast the completed transaction.

## Bitcoin Core

The repository currently includes frozen Bitcoin Core **32.0rc2 x86-64 Linux**, a release-candidate build.

SHA256:

```text
0255103718033e6aee15fa944717fc277e047b845bff1e7408af0ea732d8d0c1
```

The script verifies this before starting Core.

## Testing only

For development testing:

```bash
sudo apt install -y git && git clone --depth 1 https://github.com/Jakob-997/Core-Multisig-Helper.git && cd Core-Multisig-Helper && sudo bash setup.sh
```

Do not use a live clone of `main` for real funds. Use verified release artifacts.
