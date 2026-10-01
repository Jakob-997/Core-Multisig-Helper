# Glacier-2

Glacier-2 is a simple Bitcoin multisig generator and spender built around Bitcoin Core.

It safely generates a configurable Bitcoin Core multisig wallet, burns each signer backup to its own optical disc, and can later be used to spend from that wallet.

No seed words or private keys need to be written down by hand.

## What it does

### Generate

Glacier:

1. airgaps the computer;
2. asks for your multisig policy, with `3-7` as the default;
3. generates the independent Bitcoin Core signer wallets;
4. builds the multisig descriptor;
5. burns one signer backup to each disc;
6. verifies every disc after it is written.

For example, `3-7` means any 3 of the 7 signer backups are required to spend.

### Spend

Glacier can also be started in spend mode.

Spend mode airgaps the live computer and makes the bundled Bitcoin Core available for signing transactions with your signer backups.

## How to use it

Glacier-2 is designed for **Ubuntu 26.04.1 x86-64 Live**.

1. Download the Ubuntu 26.04.1 ISO.
2. Verify the Ubuntu ISO.
3. Create an Ubuntu boot USB.
4. Boot the computer into the Ubuntu live environment. Do not install Ubuntu.
5. On another computer, download Glacier-2 onto a separate USB.
6. Verify the Glacier-2 release.
7. Insert the Glacier USB into the live Ubuntu computer.
8. Open the Glacier folder and run:

```bash
sudo ./setup.sh
```

Glacier asks:

```text
Generate keys or spend? [generate]:
```

Choose `generate` when creating a wallet for the first time, or `spend` when signing a transaction.

## Generating a wallet

Generation requires `jq`, `nftables`, `rfkill`, `iproute2`, `xorriso`, and `eject` to be available in the live Ubuntu session.

Connect the optical writer and have one blank disc ready for each signer.

Glacier then asks:

```text
Select m-n [default 3-7]:
```

Press Enter for the default `3-7`, or enter another policy such as `2-5`.

Glacier generates the wallet, burns each signer backup, verifies each disc, and tells you when it is finished.

There is no seed phrase or private key to transcribe by hand.

## Each signer disc

Each signer disc contains:

```text
wallet.dat
descriptors.txt
```

Label each disc with a permanent marker. For a 3-7 wallet:

```text
GLACIER-2
SIGNER 1 OF 7
3-OF-7
```

Then label the others `SIGNER 2 OF 7`, `SIGNER 3 OF 7`, and so on.

Store the signer discs separately.

## Bitcoin Core

Glacier-2 includes the frozen Bitcoin Core 32.0rc2 x86-64 Linux archive used by the script.

Upstream SHA256:

```text
0255103718033e6aee15fa944717fc277e047b845bff1e7408af0ea732d8d0c1
```

Glacier-2 is experimental. Test the complete generation and spending process with disposable funds before using meaningful money.
