# Glacier-2

A deliberately small 3-of-7 Bitcoin cold-storage setup built around a frozen
Bitcoin Core release.

Glacier-2 does four things:

1. installs the bundled Bitcoin Core binary;
2. disables networking and installs a persistent software airgap;
3. creates seven independent Bitcoin Core signer wallets under one 3-of-7
   `wsh(sortedmulti(...))` policy;
4. burns one signer wallet to each of seven CD-Rs and reads every disc back.

That is the whole project.

> **Prototype:** do not use meaningful funds until you have completed the recovery
> test in [RECOVERY.md](RECOVERY.md).

## Requirements

- x86-64 PC
- Ubuntu Desktop 24.04 or 26.04
- clean/disposable installation
- CD/DVD writer
- seven new blank CD-Rs
- Internet access only while Ubuntu installs the required packages

Use full-disk encryption during Ubuntu installation if you want the laptop protected
at rest. Physically unplug Ethernet and remove or disable Wi-Fi/Bluetooth/radio
hardware where practical; software isolation cannot protect against a compromised
kernel, root account, or firmware.

## Run

On the clean Ubuntu installation:

```bash
sudo apt update
sudo apt install -y git
git clone --depth 1 https://github.com/Jakob-997/Glacier-2.git
cd Glacier-2
sudo ./setup.sh
```

The script installs dependencies before cutting networking. After the airgap is
applied, do not reconnect the machine.

The program will ask for Signer 1 through Signer 7 in order. Each disc is burned,
ejected, reinserted, and compared byte-for-byte with the ISO that was written.

For development only:

```bash
sudo ./setup.sh --test
```

`--test` performs the real airgap and creates real keys but skips CD burning.
Do not fund that installation.

Regtest can be selected with:

```bash
sudo env GLACIER_CHAIN=regtest ./setup.sh --test
```

## What is on each CD

Each signer disc contains only:

```text
wallet.dat
descriptors.txt
RECOVERY.md
DISC.txt
SHA256SUMS
```

`wallet.dat` is private and unencrypted. Keep the seven discs physically separate.
Any three different signer wallets can satisfy the policy.

`descriptors.txt` contains the complete public receive/change policy. It cannot
spend coins, but it reveals the wallet structure and derived addresses.

## Bitcoin Core trust model

Bitcoin Core 32.0rc2 for x86-64 Linux is frozen directly in this repository at:

```text
vendor/bitcoin-32.0rc2-x86_64-linux-gnu.tar.gz
```

Glacier does not download or re-authenticate Core during setup. Trusting a reviewed
Glacier commit includes trusting the Core archive in that commit.

The upstream SHA256 for the bundled archive is:

```text
0255103718033e6aee15fa944717fc277e047b845bff1e7408af0ea732d8d0c1
```

Before replacing Core, verify the new release against Bitcoin Core's official
release material and reproducible-build attestations, then review and test the new
Glacier revision.

## Files worth reviewing

The production implementation is intentionally just:

```text
setup.sh
wallets.py
```

`setup.sh` installs Core, applies the airgap, runs wallet creation, and burns the
discs. `wallets.py` constructs the seven signers and 3-of-7 descriptors using
Bitcoin Core RPC.

[RECOVERY.md](RECOVERY.md) is copied onto every disc.

## Limitations

All seven keys are generated on one machine, so a compromise during generation can
compromise the whole wallet. The software airgap is defense in depth, not a physical
airgap. Glacier does not provide secure erase, independent hardware signers, or a
formal security audit.
