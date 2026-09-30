# Validation record — 2026-09-30

Test platform: Ubuntu 24.04 under WSL, x86_64. **WSL is only a nondestructive test
environment, not a supported target for running `setup.sh`.**

Completed:

- Downloaded the official Core 32.0rc2 Linux archive. Verified the SHA256SUMS
  signatures from the two pinned primary fingerprints (Ava Chow and Hennadii
  Stepanov), then verified the selected archive's SHA256 checksum before execution.
- Checked all Bash sources with `bash -n` and ShellCheck 0.9.0.
- Tested the signature parser's positive case, missing/duplicate/untrusted
  signatures and bad/expired/revoked signature status rejection.
- Ran the production Core lifecycle helper through start, stop and restart.
  Both runs reported Core version 320000, `networkactive=false`, zero connections.
- Ran `tests/integration.py` with the verified real Core binaries. Created seven
  blank signer wallets, seven independent roots and the BIP87 regtest account
  keys. Imported each private signer policy and a private-keys-disabled watch
  policy. Validated receive/change descriptors and sample addresses across all
  eight wallets. Confirmed regeneration refuses existing wallets.
- Created seven `backupwallet` backups, made seven ISO images with xorriso,
  extracted and byte-compared their backup files, unloaded every original signer,
  and restored all seven backups under new names. Each restored wallet produced
  exactly one signature for the funded watch-wallet PSBT.
- All 21 pairs remained incomplete; all 35 triples finalized and passed Core's
  `testmempoolaccept`. No real money was involved; no external Bitcoin connections
  were enabled.

Not performed here:

- Running the destructive installer/airgap flow on physical Ubuntu, updating
  GRUB/initramfs, reboot/sleep/hotplug isolation checks or testing hardware/firmware.
- Burning actual CD-Rs, physical eject/reinsert/readback or testing a second drive.
- Full destruction of the original test installation followed by recovery using
  physical CDs only. The automated test unloads original wallets; it does not
  claim secure erasure or independent-machine recovery.
- Signet/mainnet on-chain broadcast, later-index recovery, change-spend recovery,
  wallet encryption, independent security audit or formal verification.

These remaining checks are explicit acceptance requirements in `RECOVERY.md`.
Passing static checks and regtest is **not** approval to use meaningful funds.
