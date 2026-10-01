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
5. burns one public WATCH ONLY disc for the online computer;
6. burns one private signer backup to each signer disc;
7. verifies every disc after it is written.

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

Ubuntu 26.04.1 Desktop Live already includes the tools Glacier needs for generation, including xorriso. Glacier does not install or download packages.

Connect the optical writer and have one blank disc for the WATCH ONLY wallet plus one blank disc for each signer. A 3-7 wallet therefore needs 8 discs.

Glacier then asks:

```text
Select m-n [default 3-7]:
```

Press Enter for the default `3-7`, or enter another policy such as `2-5`.

Glacier disables swap and keeps its working state in RAM. It generates the wallet, burns the WATCH ONLY disc and each signer backup, verifies every disc, and tells you when it is finished.

There is no seed phrase or private key to transcribe by hand. When generation is complete, power the live computer off completely; the temporary Glacier state disappears with the live session.

## Watch-only disc

Glacier first burns a separate WATCH ONLY disc for the online computer. It contains `watch_only.dat` and `descriptors.txt`: a Bitcoin Core watch-only wallet plus the public multisig descriptor. It contains no private keys.

## Each signer disc

Each private signer disc contains:

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


## Testing only

For quick testing, you can install Git, clone the current `main` branch, and run Glacier with:

```bash
sudo apt install -y git && git clone --depth 1 https://github.com/Jakob-997/Glacier-2.git && cd Glacier-2 && sudo ./setup.sh
```

**Do not use this shortcut for real funds.** For an actual Glacier setup, independently verify the Ubuntu ISO and the Glacier-2 release/artifacts before moving them onto the live computer.

Glacier-2 is experimental. Test the complete generation and spending process with disposable funds before using meaningful money.
