# Glacier-2

Minimal 3-of-7 Bitcoin cold storage.

Glacier-2 does four things:

1. installs the frozen Bitcoin Core build in this repository;
2. disables networking;
3. creates seven signer wallets for one 3-of-7 descriptor policy;
4. burns and verifies one signer per CD-R.

> Experimental. Complete a recovery test before using meaningful funds.

## Requirements

- x86-64 PC
- clean Ubuntu 24.04 or 26.04 install
- CD/DVD writer
- seven blank CD-Rs

Physically unplug Ethernet and disable/remove radios where practical.

## Run

```bash
sudo apt update
sudo apt install -y git
git clone --depth 1 https://github.com/Jakob-997/Glacier-2.git
cd Glacier-2
sudo ./setup.sh
```

After the airgap is applied, never reconnect the machine.

If your optical drive is not `/dev/sr0`:

```bash
sudo env GLACIER_DRIVE=/dev/sr1 ./setup.sh
```

## Each CD contains

```text
wallet.dat
descriptors.txt
RECOVERY.md
DISC.txt
SHA256SUMS
```

`wallet.dat` is private and unencrypted. Store the seven discs separately.

Any three different signer wallets can satisfy the policy.

## Trust model

Bitcoin Core 32.0rc2 for x86-64 Linux is frozen in:

```text
vendor/bitcoin-32.0rc2-x86_64-linux-gnu.tar.gz
```

Trusting a reviewed Glacier commit includes trusting that binary. Its upstream
SHA256 is:

```text
0255103718033e6aee15fa944717fc277e047b845bff1e7408af0ea732d8d0c1
```

The production code is just `setup.sh` and `wallets.py`.

See [RECOVERY.md](RECOVERY.md) before using the wallet.
