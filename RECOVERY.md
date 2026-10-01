# Glacier-2 recovery

Each CD contains one private Bitcoin Core signer wallet plus the complete public
3-of-7 policy. Any three different signer CDs are sufficient to sign.

Do not test recovery for the first time with valuable funds.

## 1. Verify the discs

On an offline machine, mount each CD read-only and run:

```bash
sha256sum --check --strict SHA256SUMS
```

Check `DISC.txt` and keep the signer numbers distinct.

## 2. Restore three signer wallets

Use Bitcoin Core 32.0rc2 on a fresh offline machine. Copy each selected
`wallet.dat` from the CD to protected local storage and restore it with a unique
name:

```bash
bitcoin-cli restorewallet signer_1 /path/to/wallet.dat
```

Repeat for two other signer discs.

Never expose `wallet.dat` or private descriptors to an online computer.

## 3. Rebuild a watch-only wallet

On a coordinator, create a blank wallet with private keys disabled and import the
two lines from `descriptors.txt`.

Use the first descriptor as receive and the second as change. Use a range large
enough to include every address you have used. Glacier initially imports indices
0 through 999.

For historical recovery, import with a timestamp before the first funding
transaction and rescan/synchronize from that point.

## 4. Test signing

Create a PSBT with the watch-only coordinator.

Process the same PSBT independently with each restored signer using
`walletprocesspsbt`. One or two different signers must not finalize. Three
different signers must finalize after their PSBTs are combined.

Before trusting the setup, perform this with disposable regtest or signet funds,
broadcast the transaction, and spend the change again.

## 5. Destructive acceptance test

Before storing meaningful funds, prove that recovery works without the original
Glacier installation:

1. create a disposable Glacier wallet;
2. verify all seven CDs;
3. successfully sign with restored backups;
4. destroy/reinstall the original test system;
5. recover using only three CDs and `descriptors.txt`;
6. complete another spend.

Ordinary file deletion is not secure erasure on SSDs. Use an appropriate
media-specific procedure for disposable test material.

## Airgap check

The Glacier machine should remain offline permanently. On the signing machine:

```bash
sudo /etc/glacier2/enforce --check
```

It should succeed. Also physically disconnect Ethernet and disable/remove radios
where practical.

If setup fails after keys have been created, preserve `/var/lib/glacier2`. Do not
delete it and rerun setup merely to obtain a clean run; that would generate a
different wallet.
