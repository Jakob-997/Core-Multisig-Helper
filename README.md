# Glacier-2

Minimal configurable m-of-n Bitcoin cold storage (default 3-of-7).

The repository contains only the setup script, this README, and the frozen Bitcoin
Core binary. The script:

1. blocks non-loopback network traffic and radios;
2. extracts the bundled Bitcoin Core;
3. asks for m and n, then creates n independent BIP87 signer wallets for one
   m-of-n `wsh(sortedmulti(...))` multipath descriptor;
4. burns one signer to each of n CD-Rs and verifies each disc byte-for-byte.

## Setup

Use a clean x86-64 Ubuntu 24.04/26.04 installation. Before going offline:

```bash
sudo apt update
sudo apt install -y git jq nftables rfkill xorriso eject
git clone --depth 1 https://github.com/Jakob-997/Glacier-2.git
cd Glacier-2
```

Connect the optical writer and have one blank CD-R per signer ready. Physically unplug
Ethernet. Then run:

```bash
sudo ./setup.sh
```

The script applies the software airgap before extracting or running Bitcoin Core.
Do not reconnect the machine.

If the writer is not `/dev/sr0`:

```bash
sudo env GLACIER_DRIVE=/dev/sr1 ./setup.sh
```

At startup, press Enter for the default 3-of-7 policy or enter your own m and n
(1 <= m <= n <= 20). Each disc contains only `wallet.dat` and `descriptors.txt`.
Label them Signer 1 through Signer n and store them separately. Any m distinct
signer wallets can satisfy the policy.

## Recovery

On a fresh offline Bitcoin Core 32.0rc2 installation, restore any m distinct
`wallet.dat` files with unique wallet names. Create a blank watch-only wallet and
import the single multipath descriptor from `descriptors.txt`; Core expands
`<0;1>` into receive and change branches. Glacier initially imports indices
0-999.

Create a PSBT with the watch-only wallet, process it independently with m
restored signers, combine the PSBTs, and finalize. Prove this with disposable funds
before using meaningful money.

If setup fails after keys exist, preserve `/var/lib/glacier2`. Do not delete it
and rerun setup merely to obtain a clean run.

## Bitcoin Core

`bitcoin-core.tar.gz` is the official Bitcoin Core 32.0rc2 x86-64 Linux archive.
Trusting a reviewed Glacier commit includes trusting this binary.

Upstream SHA256:

```text
0255103718033e6aee15fa944717fc277e047b845bff1e7408af0ea732d8d0c1
```

Glacier is experimental. Physically isolating the signing computer remains stronger
than software isolation.
