# Core Multisig Helper

```text
             /\
            /  \
           / /\ \
          /_/  \_\
     CORE MULTISIG HELPER
```

A small Bitcoin Core helper for creating and using offline multisig wallets.

Core Multisig Helper is intentionally narrow. It generates independent Bitcoin Core signer wallets in an airgapped Ubuntu Live session, writes each signer backup to its own optical disc, creates a separate public watch-only backup, and later helps you load one signer at a time for offline PSBT signing.

It does **not** try to be a complete wallet application or replace your online Bitcoin node.

> **Status:** polished testing draft. Test the complete generate → restore → sign → broadcast workflow with disposable funds before using meaningful money.

## Overview

For an `M-of-N` wallet:

- `M` is the number of different signer backups required to spend.
- `N` is the total number of private signer backups.
- Core Multisig Helper creates **N private signer discs + 1 public WATCH ONLY disc**.
- Example: `3-7` requires 3 signers out of 7 and uses **8 discs total**.

Private keys are generated only after the machine has been airgapped. Swap is disabled and all working wallet state is kept under RAM-backed `/dev/shm`. Each signer should later be used in a **fresh Ubuntu Live session**.

There are no seed words to copy by hand.

## What you need

Prepare these before creating a wallet:

- **Two USB drives**
  - **USB 1 — Ubuntu:** verified Ubuntu 26.04.1 x86-64 Desktop Live.
  - **USB 2 — Transfer:** Core Multisig Helper plus, later, the PSBT being signed.
- **A CD/DVD writer and reader** visible to Linux as `/dev/sr0`.
- **N + 1 blank CD-Rs**
  - N private signer discs.
  - 1 public WATCH ONLY disc.
- **A permanent marker** for labeling every disc immediately.
- **An online Bitcoin wallet/node** for creating PSBTs, monitoring the wallet, and broadcasting completed transactions.

For a `3-7` setup, bring 8 blank discs.

## 1. Prepare Ubuntu

1. Download the Ubuntu 26.04.1 x86-64 Desktop ISO from Ubuntu.
2. Verify the ISO using Ubuntu's published verification information.
3. Write it to **USB 1**.
4. Boot the computer from USB 1 and choose the live environment.
5. **Do not install Ubuntu to the computer.**

The signing computer is expected to be disposable: boot live, perform one operation, then power it completely off.

## 2. Prepare the transfer USB

On another computer:

1. Obtain a released/tagged copy of Core Multisig Helper.
2. Verify the release/artifacts before using it with real funds.
3. Put the project on **USB 2**.

USB 2 is also the transfer media used later for PSBT files. It should not contain signer private-key backups.

## 3. Generate a wallet

Boot a fresh Ubuntu Live session.

Insert:

- USB 2 containing Core Multisig Helper;
- the optical writer;
- your blank CD-Rs.

Open the project folder and run:

```bash
sudo ./setup.sh
```

The program asks:

```text
Select mode: generate or spend:
```

Enter:

```text
generate
```

Then enter the multisig policy in `m-n` format:

```text
Enter multisig policy in m-n format (for example 3-7):
```

For example:

```text
3-7
```

means **3 different signers are required from 7 total signer backups**.

There is no default. You must explicitly choose the mode and policy.

Before any private keys are generated, the program disables swap, applies the firewall airgap, stops network managers, blocks radios, brings network interfaces down, and prints:

```text
AIRGAP ACTIVE — networking disabled before key generation.
```

It then generates the wallet in RAM.

## 4. Burn the backups

Core Multisig Helper first asks for the **WATCH ONLY** disc.

That public disc contains:

```text
watch_only.dat
descriptors.txt
```

It contains the public multisig wallet information and **no private keys**.

Then the program asks for each private signer disc in order.

Each private signer disc contains:

```text
wallet.dat
descriptors.txt
```

After writing each disc, the program ejects it, asks you to reinsert it, and byte-compares the disc against the ISO that was written.

Do not consider a backup complete until the program reports that disc as verified.

### Label immediately

For a `3-7` wallet, label the public disc something like:

```text
CORE MULTISIG HELPER
WATCH ONLY
3-OF-7
PUBLIC
```

Label the private discs:

```text
CORE MULTISIG HELPER
SIGNER 1 OF 7
3-OF-7
PRIVATE
```

then `SIGNER 2 OF 7`, `SIGNER 3 OF 7`, and so on.

Store the private signer discs separately.

When generation is completely finished, **power the live computer off**. The temporary RAM state disappears with the session.

## 5. Set up the online wallet

The online side is outside the core purpose of this project. Its job is to:

- monitor the public wallet;
- create unsigned or partially signed PSBTs;
- receive signed PSBTs back from USB 2;
- broadcast the completed transaction.

### Preferred: your own Bitcoin Core node

The preferred online setup is your own Bitcoin Core node using the WATCH ONLY wallet.

For privacy, Bitcoin Core can be configured to use Tor.

If you use Tails as the online workstation, remember that running a persistent full node requires persistent or external blockchain storage. That setup is outside this project's scope.

### Alternative: Sparrow

Sparrow can also create compatible PSBTs.

You can connect Sparrow to your own node, or to a public Electrum server. If using a public Electrum server, using Tor is strongly preferable for privacy.

A public Electrum server adds privacy and data-trust assumptions compared with using your own Bitcoin Core node. It still does not possess your signer private keys. Treat the offline signer as the final checkpoint: verify the destination, amount, and fee before signing.

## 6. Sign a PSBT

Put the PSBT from your online wallet onto **USB 2**.

Boot a **fresh Ubuntu Live session** and insert USB 2.

Run:

```bash
sudo ./setup.sh
```

Choose:

```text
spend
```

The machine is airgapped before any signer wallet is loaded. You will see:

```text
AIRGAP ACTIVE — networking disabled before signer wallet loading.
```

The program then asks you to insert and mount **one** signer backup disc.

It:

1. finds exactly one `wallet.dat`;
2. confirms that `descriptors.txt` is present;
3. reads the public descriptor to determine the `M-of-N` policy;
4. copies the signer wallet from the disc into RAM;
5. leaves the backup disc itself untouched;
6. opens the RAM copy in the bundled Bitcoin Core GUI.

For a `3-7` wallet it will tell you that **3 different signer backups out of 7 total** are required.

In Bitcoin Core:

1. Load the PSBT from USB 2.
2. Review the transaction carefully.
3. Sign it.
4. Save the partially signed PSBT back to USB 2.
5. Close Bitcoin Core.
6. Power the computer completely off.

Then boot another fresh Ubuntu Live session and repeat the process with a **different signer disc**.

Continue until `M` different signer backups have signed.

Example:

```text
3-of-7 → sign with any 3 different signer discs
```

Once the signing threshold is satisfied, take USB 2 back to the online computer and broadcast the completed transaction from your node/wallet.

## Security model

Core Multisig Helper deliberately keeps the design small:

- Ubuntu Live instead of an installed signing OS.
- No network access while generating or loading signer keys.
- Kernel nftables DROP policy plus radio/interface shutdown.
- Bitcoin Core additionally runs with networking disabled.
- Swap disabled.
- Working wallet state stored in RAM-backed `/dev/shm`.
- One private signer per optical disc.
- One signer loaded per fresh live session.
- Private signer media is copied into RAM rather than used as Core's writable wallet.
- Public descriptor/watch-only backup is kept separate from private signer backups.

During initial generation, all signer keys necessarily coexist on the one clean offline generation machine. After backups are created, normal signing uses only one signer per fresh session.

## Bitcoin Core

The repository currently includes the frozen Bitcoin Core **32.0rc2 x86-64 Linux** archive used by the script.

The script verifies this SHA256 before starting Core:

```text
0255103718033e6aee15fa944717fc277e047b845bff1e7408af0ea732d8d0c1
```

Before treating this project as finalized for real funds, the bundled Core version should be reviewed/frozen again and the entire hardware workflow retested.

## Testing only

For quick development testing, you can install Git, clone the current `main` branch, and launch the helper:

```bash
sudo apt install -y git && git clone --depth 1 https://github.com/Jakob-997/Glacier-2.git Core-Multisig-Helper && cd Core-Multisig-Helper && sudo ./setup.sh
```

**Do not use this shortcut for real funds.** A real setup should use independently verified Ubuntu and Core Multisig Helper release artifacts rather than trusting a live clone of `main`.
