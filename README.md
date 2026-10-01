# Glacier-2

Minimal **configurable m-of-n Bitcoin cold storage**.

**3-of-7 is only the default.** When Glacier starts, it asks for `m` and `n`.
Press Enter for 3-of-7, or choose another policy. Glacier supports
`1 <= m <= n` with `2 <= n <= 20`.

The repository contains only:

- `setup.sh`
- this README
- the frozen Bitcoin Core binary

The script:

1. asks for your m-of-n policy;
2. blocks non-loopback network traffic and radios;
3. extracts and starts the bundled Bitcoin Core with networking disabled;
4. creates `n` independent BIP87 signer wallets;
5. builds one `wsh(sortedmulti(m,...))` multipath descriptor;
6. burns one signer to each of `n` CD-Rs and verifies each disc byte-for-byte.

## Setup

Use a clean x86-64 Ubuntu 24.04/26.04 installation.

Before running Glacier, while still online, make sure these packages are installed:
`git`, `jq`, `nftables`, `rfkill`, `xorriso`, and `eject`.

Clone or copy this repository onto the machine, connect the optical writer at
`/dev/sr0`, have one blank CD-R per signer ready, and physically unplug Ethernet.

Then there is one Glacier command:

```bash
sudo ./setup.sh
```

At startup:

```text
m [3]:
n [7]:
```

Press Enter twice for 3-of-7, or enter your own m and n.

After the airgap is applied, do not reconnect the machine.

## Each CD

Each disc contains only:

```text
wallet.dat
descriptors.txt
```

Label the discs Signer 1 through Signer n and store them separately.
Any m distinct signer wallets can satisfy the policy.

## Recovery

On a fresh offline Bitcoin Core 32.0rc2 installation, restore any m distinct
`wallet.dat` files with unique wallet names.

Create a blank watch-only wallet and import the single multipath descriptor from
`descriptors.txt`. Core expands `<0;1>` into receive and change branches.
Glacier initially imports indices 0-999.

Create a PSBT with the watch-only wallet, process it independently with m restored
signers, combine the PSBTs, and finalize.

Prove recovery with disposable funds before using meaningful money.

If setup fails after keys exist, preserve `/var/lib/glacier2`. Do not delete it
and rerun setup just to get a clean run.

## Bitcoin Core

`bitcoin-core.tar.gz` is the official Bitcoin Core 32.0rc2 x86-64 Linux archive.
Trusting a reviewed Glacier commit includes trusting this binary.

Upstream SHA256:

```text
0255103718033e6aee15fa944717fc277e047b845bff1e7408af0ea732d8d0c1
```

Glacier is experimental. Physical isolation remains stronger than software isolation.
