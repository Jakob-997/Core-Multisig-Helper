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

## Desktop identity / mainnet default update

- Changed the setup default to mainnet; test networks now require an explicit option.
- Re-ran ShellCheck, Bash syntax and Python compile/unit checks after adding the
  desktop module. Five unit tests pass, including identity non-regeneration and
  isolated mocked GNOME preferences/launcher/watch-copy behavior.
- Rendered and visually inspected a 1920×1080 example recognition wallpaper.
  Verified the stored random code/color and refusal to replace an existing identity.
- Ran `tests/mainnet_qt.py` with the verified Core binaries, no funds and disabled
  networking. All seven signers and the watch wallet passed mainnet BIP87
  descriptor/address checks. Qt's supported minimal display backend opened a
  separate watch-only backup copy, reported private keys disabled and zero peers,
  and generated a mainnet `bc1q` address. The desktop launcher uses XCB/XWayland.
- Actual GNOME wallpaper application, lock-screen appearance, desktop trust and
  dock pinning remain **unverified on a physical desktop**. The settings unit test
  uses mocks; it does not establish live desktop compatibility. Check these during
  your hardware acceptance run. No Windows desktop settings were changed.

## Unattended setup / no-CD test update

- Bundled the official Core v32.0rc2 SVG and upstream MIT license; a unit test
  verifies the icon's exact upstream Git blob identity, including line endings.
- Removed setup/hardening/mainnet/identity confirmation prompts. Added `--test`
  to select the real setup modules without the CD module or optical-device probes.
  New Bash option tests cover both module lists and unknown-option rejection.
- Expanded installed radio-driver blocking and made boot-enforcement failure
  request emergency isolation. The boot service rechecks the kernel module lock.
- Python compilation, signature tests and exact-asset tests run locally on Windows.
  Linux checks are provided by the added GitHub Actions workflow. Local WSL
  execution is unavailable under this session's permissions; earlier Linux
  validation results above apply to the earlier revisions only.
- No physical hardening, reboot failure-path, GNOME or CD tests were performed
  for this update. `--test` itself is destructive and is not run on this workstation.


## Test-mode signer visibility / documentation refresh

- Updated `--test` desktop behavior so the user-owned Bitcoin-Qt datadir receives
  copies of `signer_1` through `signer_7` in addition to `watch_only`, and the
  launcher loads all eight wallets for inspection. Production mode remains
  watch-only.
- Added unit coverage for the explicit `test-signers` desktop mode and retained
  the production `watch-only` default.
- GitHub Actions `Prototype checks` completed successfully for the signer-wallet
  code change (`22f2bbac`) and the subsequent curl/bootstrap and README/technical
  documentation changes checked so far.
- Reorganized the project documentation so `README.md` is the operational setup
  guide and `TECHNICAL.md` holds architecture, verification, airgap, and failure
  details. `RECOVERY.md` remains the destructive acceptance procedure.
- No new physical Ubuntu, TPM/FDE, optical-disc, reboot, or hardware-isolation
  acceptance test was performed as part of this documentation/update pass.
