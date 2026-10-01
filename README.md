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

Core Multisig Helper is intentionally narrow, but it creates a real wallet you can actually use. It helps you generate the multisig keys and backups, then later load those signer backups and spend from the same wallet with PSBTs.

This is **not a complete Bitcoin custody guide unto itself**. It focuses on key generation, signer backups, and offline signing. You choose the M-of-N policy, storage locations, inheritance plan, online wallet, and broader operational security that fit your own threat model.

> **Status:** working testing draft, **not audited**. The multisig construction follows the WSH/BIP87 `sortedmulti` approach used by the Bitcoin Core multisig wizard work in PR #36325. The generate, watch-only, sign, combine/finalize, backup, restore, and signer-loading paths have been exercised in automated tests, but the complete hardware workflow should still be tested with disposable funds before using meaningful money.

## Security design

The design tries to keep the trusted code and operating procedure small.

- **Bitcoin Core does the wallet work.** The helper uses Bitcoin Core for key generation, descriptors, wallet backups, PSBT signing, and wallet recovery rather than implementing Bitcoin cryptography itself.
- **Ubuntu Live is disposable.** Generation and signing happen from a fresh Ubuntu Live session instead of an installed signing OS.
- **Networking is disabled before private keys are generated or loaded.** The script installs an nftables DROP policy, stops network managers, blocks radios, brings interfaces down, and starts Core with networking disabled.
- **Swap is disabled.** Working state is kept under RAM-backed `/dev/shm`.
- **One signer per disc.** Each private signer gets its own optical backup.
- **One signer per fresh signing session.** A signer disc is copied into RAM, used for signing, then the computer is powered off before another signer is used.
- **The public wallet is separate.** A WATCH ONLY disc contains the descriptor and watch-only wallet but no private signing keys.

During initial wallet generation, all N signer keys necessarily coexist on the one offline generation computer. After backup creation, normal spending uses only one signer in each fresh live session.

### Strongly recommended: physically airgap the signing computer

The script creates a **software airgap**, but software controls are still software. A sufficiently capable pre-existing compromise, kernel exploit, firmware compromise, or similar failure could in principle bypass software-only network restrictions.

For higher assurance, physically remove wireless networking hardware before using the machine.

On many laptops, Wi‑Fi and Bluetooth share the same removable M.2 radio card. If your laptop also has a WWAN/cellular/mobile-data modem, remove that module as well. Verify the hardware layout for your specific computer before assuming one card covers every radio.

Some laptops have soldered wireless hardware and cannot be physically stripped without board-level work. If physical airgapping matters to your threat model, use a laptop with removable radio modules or a desktop with no built-in wireless hardware. Desktops are often easier to inspect and commonly use removable PCIe/M.2 networking hardware.

Also disconnect Ethernet and any other networking adapters. The goal is simple: the signing computer should have **no physical path to a network** while private keys are being generated or used.

Physical removal is not required for the script to function; it is an additional defense against the small residual risk of software airgap failure.

### Important privacy and physical-access tradeoff

The signer discs are **not encrypted**. Each signer disc contains an unencrypted Bitcoin Core `wallet.dat` plus the public `descriptors.txt` file.

Anyone who gets access to one signer disc can recover that signer's private key material. Because the public descriptor is also present, they can derive the wallet's addresses and monitor its past and future on-chain activity.

They still cannot spend unless they obtain enough different signer backups to meet the threshold. For example, with a 2-of-4 wallet, one stolen signer disc is insufficient; two different signer backups are required to authorize a spend.

This is a deliberate tradeoff. The disadvantage is weaker privacy and no at-rest encryption on the signer media. The advantage is simplicity: there is no additional passphrase, encryption key, recovery secret, or decryption procedure that can itself be lost, forgotten, or implemented incorrectly.

## Wallet layout

For an `M-of-N` wallet:

- `M` is the number of different signer backups required to spend.
- `N` is the total number of private signer backups.
- Core Multisig Helper creates **N private signer discs + 1 public WATCH ONLY disc**.
- Example: `2-4` requires 2 signers out of 4 and uses **5 discs total**.

There are no seed words to copy by hand.

## What you need

Prepare these before creating a wallet:

- **Two USB drives**
  - **USB 1 — Ubuntu:** verified Ubuntu 26.04.1 x86-64 Desktop Live.
  - **USB 2 — Transfer:** the Core Multisig Helper release and, later, the PSBT being signed.
- **A CD/DVD writer and reader** visible to Linux as `/dev/sr0`.
- **N + 1 blank CD-Rs**
  - N private signer discs.
  - 1 public WATCH ONLY disc.
- **A permanent marker** for labeling every disc immediately.
- **An online Bitcoin wallet/node** for monitoring the wallet, creating PSBTs, and broadcasting completed transactions.

For a `2-4` setup, bring 5 blank discs.

## 1. Prepare Ubuntu

1. Download the Ubuntu 26.04.1 x86-64 Desktop ISO from Ubuntu.
2. Verify the ISO using Ubuntu's published verification information.
3. Write it to **USB 1**.
4. Boot the signing computer from USB 1 and choose the live environment.
5. **Do not install Ubuntu to the computer.**

If you are physically airgapping the machine, remove its wireless/WWAN hardware before beginning the real wallet-generation session.

The signing computer is treated as disposable: boot live, perform one operation, then power it completely off.

## 2. Prepare Core Multisig Helper

On an online computer:

1. Download the Core Multisig Helper **release archive**.
2. Verify the release and any published checksums/signatures before using it with real funds.
3. Extract the release.
4. Copy the extracted **Core-Multisig-Helper** folder to **USB 2**.

USB 2 is also used later to move PSBT files between the online wallet and the offline signing computer. It should not contain private signer backups.

## 3. Generate a wallet

Boot a fresh Ubuntu Live session.

Insert USB 2, connect the optical writer, and have your blank CD-Rs ready.

Open a terminal and change into the extracted project directory on USB 2:

```bash
cd /path/to/Core-Multisig-Helper
```

Then run:

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

Then choose the multisig policy in `m-n` format:

```text
Enter multisig policy in m-n format (for example 2-4):
```

For example:

```text
2-4
```

means **2 different signers are required from 4 total signer backups**.

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

The program then asks for each private signer disc in order.

Each private signer disc contains:

```text
wallet.dat
descriptors.txt
```

After writing each disc, the program ejects it, asks you to reinsert it, and byte-compares the disc against the ISO that was written.

Do not consider a backup complete until the program reports that disc as verified.

### Label immediately

For a `2-4` wallet, label the public disc something like:

```text
CORE MULTISIG HELPER
WATCH ONLY
2-OF-4
PUBLIC
```

Label the private discs:

```text
CORE MULTISIG HELPER
SIGNER 1 OF 4
2-OF-4
PRIVATE
```

then `SIGNER 2 OF 4`, `SIGNER 3 OF 4`, and so on.

Store the private signer discs separately.

When generation is completely finished, **power the live computer off**. The temporary RAM state disappears with the session.

## 5. Set up the online wallet

The online side creates PSBTs, monitors the public wallet, receives signed PSBTs back from USB 2, and broadcasts completed transactions.

### Preferred: your own Bitcoin Core node

The preferred online setup is your own Bitcoin Core node using the WATCH ONLY wallet.

For privacy, Bitcoin Core can be configured to use Tor.

If you use Tails as the online workstation, remember that maintaining a persistent full node requires persistent or external blockchain storage. That setup is outside this project's scope.

### Alternative: Sparrow

Sparrow can also create compatible PSBTs.

You can connect Sparrow to your own node or to a public Electrum server. If using a public Electrum server, Tor is strongly preferable for privacy.

A public Electrum server adds privacy and data-trust assumptions compared with your own Bitcoin Core node. It does not possess your signer private keys. The offline signer remains the final checkpoint: verify the destination, amount, and fee before signing.

## 6. Sign a PSBT

Create the PSBT using the online wallet and save it to **USB 2**.

Boot a **fresh Ubuntu Live session**, insert USB 2, open a terminal, and change into the project directory:

```bash
cd /path/to/Core-Multisig-Helper
sudo ./setup.sh
```

Choose:

```text
spend
```

The machine is airgapped before any signer wallet is loaded:

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

For a `2-4` wallet it tells you that **2 different signer backups out of 4 total** are required.

In Bitcoin Core:

1. Load the PSBT from USB 2.
2. Review the destination, amount, and fee carefully.
3. Sign it.
4. Save the partially signed PSBT back to USB 2.
5. Close Bitcoin Core.
6. Power the computer completely off.

Then boot another fresh Ubuntu Live session and repeat with a **different signer disc**.

Continue until `M` different signer backups have signed.

Example:

```text
2-of-4 → sign with any 2 different signer discs
```

Once the threshold is satisfied, take USB 2 back to the online computer and broadcast the completed transaction from your node/wallet.

## Bitcoin Core

The repository currently includes the frozen Bitcoin Core **32.0rc2 x86-64 Linux** archive used by the script.

The script verifies this SHA256 before starting Core:

```text
0255103718033e6aee15fa944717fc277e047b845bff1e7408af0ea732d8d0c1
```

Before treating this project as finalized for real funds, the bundled Core version should be reviewed/frozen again and the complete hardware workflow retested.

## Testing only

For quick development testing, you can install Git, clone the current `main` branch, and launch the helper:

```bash
sudo apt install -y git && git clone --depth 1 https://github.com/Jakob-997/Core-Multisig-Helper.git && cd Core-Multisig-Helper && sudo ./setup.sh
```

**Do not use this shortcut for real funds.** A real setup should use independently verified Ubuntu and Core Multisig Helper release artifacts rather than trusting a live clone of `main`.
