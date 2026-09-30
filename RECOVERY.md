# Recovery and acceptance test

**Do this before sending meaningful bitcoin to the wallet.**

The intended recovery property is stronger than merely restoring `wallet.dat`:
a threshold set of written shares must recreate the exact same Bitcoin Core BIP84
descriptors and addresses on a separate clean installation.

## A. Verify a written share set

Use a clean offline Ubuntu machine with a reviewed copy of Glacier-2, the pinned
Shamir helper, Bitcoin Core, the public `manifest.json`, and only the threshold
number of shares needed for the test.

Do not bring all copies together unless necessary.

Start Bitcoin Core with networking disabled in a fresh datadir, then run:

```bash
sudo python3 lib/recovery.py recreate \
  /opt/glacier2/core/bin/bitcoin-cli \
  /path/to/fresh-core-datadir \
  main \
  /opt/glacier2/shamir-helper \
  /path/to/manifest.json
```

Enter the requested shares from paper.

The command must end with:

```text
Recovery verified: descriptors exactly match the original wallet.
```

It creates an encrypted `recovered` wallet from the reconstructed 32-byte secret,
reimports the deterministic xprv, asks Bitcoin Core to regenerate the BIP84
descriptors, and requires those descriptors to exactly match the original public
manifest.

Check several receive and change addresses independently against the original
manifest/watch wallet.

## B. Test the encrypted wallet backup

On an offline test/recovery Core instance, restore the encrypted
`/var/lib/glacier2/recovery/wallet.dat`.

Confirm the wallet is locked. Then reconstruct the threshold shares and derive the
passphrase with the recovery utility rather than typing a separate password.

The original installed signer can be unlocked locally with:

```bash
sudo python3 lib/recovery.py unlock \
  /opt/glacier2/core/bin/bitcoin-cli \
  /var/lib/glacier2/core-data \
  main \
  /opt/glacier2/shamir-helper
```

The passphrase is derived internally and is not printed. The default unlock period
is five minutes.

## C. Spend test

Before significant funds:

1. use the watch-only wallet to create an unsigned PSBT spending a trivial test
   amount;
2. unlock the offline signer from a threshold of written shares;
3. sign the PSBT;
4. finalize it and verify the transaction;
5. confirm the signer locks again;
6. repeat once using a restored encrypted `wallet.dat` on a clean recovery machine.

For automated development testing, `tests/integration.py` performs the equivalent
on regtest with a deterministic disposable master secret. It verifies all 3-of-5
share combinations, restores the encrypted wallet backup, confirms a locked wallet
cannot fully sign, unlocks it from the reconstructed secret, finalizes a spend, and
recreates the exact original descriptors.

## Failure rules

Stop and investigate if:

- any written share fails its checksum;
- shares report different set IDs or policies;
- any threshold combination fails reconstruction;
- recreated descriptors differ by even one character;
- addresses differ;
- an encrypted wallet signs while supposedly locked;
- network isolation is not intact.

Do not solve a failed recovery rehearsal by deleting the original wallet and
generating new keys. Preserve the evidence and determine what failed first.

## Long-term storage

The written shares are the ultimate recovery material. Store them in physically
separate locations appropriate to the selected threshold.

The encrypted `wallet.dat` is only a convenience copy. It may be stored
redundantly on ordinary electronic media because it is encrypted by a high-entropy
passphrase derived from the Shamir master secret.

Also retain the public `manifest.json` and `descriptors.txt`. They cannot spend
funds, but they are privacy-sensitive and make recovery verification easier.
