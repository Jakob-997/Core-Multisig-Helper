# Glacier-2

Minimal **configurable m-of-n Bitcoin cold storage**.

**3-of-7 is only the default.** When Glacier starts, it asks for `m` and `n`.
Press Enter for 3-of-7, or choose another policy.

The repository contains only:

- `setup.sh`
- this README
- the frozen Bitcoin Core binary

The script:

1. asks for your m-of-n policy;
2. airgaps the running system by blocking all non-loopback network traffic and radios;
3. extracts and starts the bundled Bitcoin Core with networking disabled;
4. creates `n` independent BIP87 signer wallets;
5. builds one `wsh(sortedmulti(m,...))` multipath descriptor;
6. burns one signer to each of `n` CD-Rs and verifies each disc byte-for-byte.

## Setup

Use a clean x86-64 Ubuntu 24.04/26.04 installation.

Before running Glacier, while still online, make sure these packages are installed:
`git`, `jq`, `nftables`, `rfkill`, `xorriso`, and `eject`.

For real use, download a specific Glacier release and verify it before running it.

For testing, run:

```bash
sudo apt install -y git && git clone --depth 1 --branch simplify-auditability https://github.com/Jakob-997/Glacier-2.git && cd Glacier-2 && sudo ./setup.sh
```

Connect the optical writer at `/dev/sr0`, have one blank CD-R per signer ready,
and physically unplug Ethernet.

Then run Glacier:

```bash
sudo ./setup.sh
```

At startup:

```text
Select m-of-n [3-of-7]:
```

Press Enter for the default 3-of-7, or type another policy such as `2-5`, `2-of-5`, or `2 of 5`.

Glacier's software airgap blocks all network traffic except local loopback traffic,
and `rfkill` blocks radios. Bitcoin Core is also started with networking disabled.

This airgap applies to the current boot; it is not a permanent OS modification.
Do not reconnect the machine, and physically unplug Ethernet and disable/remove
radios where practical.

## Each CD

Each disc contains only:

```text
wallet.dat
descriptors.txt
```

After each disc verifies, write on the top of the CD with a permanent marker:

```text
GLACIER-2
SIGNER 1 OF n
m-OF-n
```

Use the actual signer number and your actual m-of-n policy on each disc. For example,
a 3-of-7 setup should be labeled `SIGNER 1 OF 7`, `3-OF-7`, then
`SIGNER 2 OF 7`, and so on.

Store the discs separately. Any m distinct signer wallets can satisfy the policy.

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
