# Validation record — single-sig Shamir redesign

Date: 2026-09-30

## Automated checks implemented

The branch includes tests for:

- BIP32 master-xprv serialization using a fixed 32-byte vector;
- deterministic domain-separated wallet-passphrase derivation;
- building the Shamir/Bytewords helper from exact pinned Blockchain Commons
  commits;
- the published Bytewords `Hello\\n` vector;
- bc-shamir split/recovery;
- 2-of-3, 3-of-5, and 3-of-7;
- reconstruction of every threshold combination;
- rejection of a corrupted Bytewords share;
- rejection of mixed share sets;
- desktop watch-only and one-signer test modes.

The disposable real-Core regtest integration test is designed to verify:

- a fixed test master secret split 3-of-5;
- all ten 3-of-5 combinations reconstruct identically;
- a single encrypted Core signer wallet;
- Core-generated native-SegWit BIP84 descriptors;
- matching watch-only addresses;
- encrypted `wallet.dat` backup and restore;
- locked-wallet signing failure/incompleteness;
- unlock from the reconstructed master secret;
- successful single-signature PSBT finalization and mempool acceptance;
- exact descriptor recreation from the same recovered master secret.

The mainnet/Qt smoke test uses no funds and no peers and checks `bc1q` BIP84
addresses plus a private-keys-disabled watch-only desktop copy.

## Still required before meaningful funds

- Review the complete pull request and dependency pins.
- Run the real-Core integration test with the verified 32.0rc2 binaries.
- Run the mainnet/Qt smoke test.
- Run the complete installer on disposable physical Ubuntu hardware.
- Reboot and test nftables/rfkill/driver/module-lock persistence.
- Perform a real handwritten-share ceremony for each supported policy.
- Destroy a disposable original wallet and recover solely from the written shares.
- Restore the encrypted wallet backup on a second clean offline machine.
- Perform a tiny end-to-end spend test.
- Obtain independent security review of the final Glacier wrapper.

Passing CI is not an independent security audit and is not approval to protect
meaningful funds.
