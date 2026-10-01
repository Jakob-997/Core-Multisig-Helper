# Recovery

Any three different Glacier signer CDs can spend.

## Verify

Mount each disc read-only:

```bash
sha256sum --check --strict SHA256SUMS
```

Keep signer numbers distinct.

## Restore

On a fresh offline Bitcoin Core 32.0rc2 installation, restore three wallets:

```bash
bitcoin-cli restorewallet signer_1 /path/to/wallet.dat
```

Repeat with two other signer discs.

Never put `wallet.dat` or private descriptors on an online computer.

## Watch-only wallet

Create a blank wallet with private keys disabled and import the two lines from
`descriptors.txt`. The first is receive; the second is change. Glacier initially
uses range 0-999. Extend the range if later addresses were used.

For historical recovery, rescan from before the first funding transaction.

## Test signing

Create a PSBT with the watch-only wallet. Process it separately with three restored
signers, combine the PSBTs, and finalize.

One or two different signers must not finalize. Three must finalize.

Before using meaningful funds, prove this with disposable regtest or signet funds,
then destroy/reinstall the original test machine and repeat recovery using only
three CDs.

## Airgap

Keep the signing machine permanently offline. Physically disconnect Ethernet and
disable/remove radios where practical.

If setup fails after keys exist, preserve `/var/lib/glacier2`. Do not delete it
and rerun setup just to get a clean run.
