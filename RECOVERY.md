# Destructive recovery and spend-test checklist

**Prototype. No meaningful funds until this checklist passes.** First complete
regtest, then a signet exercise on your actual equipment. A successful disc hash
is not proof of wallet recovery or spending ability. Every disc is unencrypted.

## Before destroying anything

- Record the network, Core version, both public descriptors and their checksums,
  signer numbers, seven root fingerprints/xpubs, and the receive/change sample
  addresses from `manifest.json`. Keep independent public copies.
- Record the recognition code and color from `identity.json` on separate paper.
  Compare them with the desktop before use; check lock/unlock behavior too. Modern
  GNOME may blur the lock-screen text. These are copyable recognition cues, not
  proof of integrity or protection against exfiltration. The desktop Core shortcut
  contains only a watch-only copy; private signer recovery still uses the CDs.
- Verify all seven physical CDs on a second optical reader: mount read-only,
  enter the disc directory, and run `sha256sum --check --strict SHA256SUMS`.
  Confirm the signer number in `DISC.txt`, that there is exactly one `wallet.dat`,
  and that the policy and samples agree across all discs. Never upload wallet.dat.
- Restore each disc on a fresh offline test installation using verified Core
  32.0rc2. A typical RPC, with your dedicated datadir/chain/port options, is
  `bitcoin-cli restorewallet restored_1 /absolute/path/to/wallet.dat`.
  Use unique names; never overwrite an existing wallet. Copy the backup from the
  read-only disc to protected local storage first if needed.
- Check `getwalletinfo` and `listdescriptors false` for each restored signer.
  Confirm both active receive/change descriptors match the public policy and
  that the correct signer alone can produce a signature. Never use
  `listdescriptors true` in logs, screenshots or an online environment.
- Create a separate **blank, private-keys-disabled** watch wallet on a test
  coordinator. Use `createwallet` with `disable_private_keys=true blank=true`.
  Import the two lines of `descriptors.txt` using `importdescriptors`, with
  `active=true`, `internal=false` for receive / `true` for change, and an adequate
  `range`. For recovery use `timestamp=0` (or an independently known earlier
  birthday), NOT `now`. Sync/rescan from before the funding block. A pruned node
  may need missing historical blocks. Extend beyond index 999 when necessary.
- Compare receive and change addresses at indices 0, 1, 2 and a later index
  using `deriveaddresses`, then compare against the original public records.
- Fund only a disposable regtest/signet address. Build a PSBT using the watch
  coordinator's `walletcreatefundedpsbt` and transfer it offline. Confirm inputs,
  destination, amount, fee, and change against an independently trusted display.

## Spend recovery, then destructive recovery

- On restored signers, run `walletprocesspsbt` separately on the original PSBT.
  Check each contributes exactly its own signature using `decodepsbt`. Export
  only PSBTs, never a signer database or private descriptor to the coordinator.
- Use `combinepsbt` then `finalizepsbt`: one or two distinct signers must remain
  incomplete. Three distinct restored signers must finalize. Repeating one
  signer's signature must not count as another signer.
- Test every signer and preferably all 35 triples. At minimum use different
  triples covering all seven signers, both receive and change spends, and later
  address indices. Run `testmempoolaccept`, broadcast the test transaction, mine
  or wait for confirmation, and spend its change in a second transaction.
- Only after preliminary recovery succeeds, **destroy the original TEST wallet
  installation and every TEST staging/ISO copy** so none can assist recovery.
  This step is intentionally manual: confirm the exact device and directories,
  verify this is disposable test material, then use an appropriate media-specific
  sanitization/reinstallation procedure. Ordinary file deletion is not secure
  erasure on SSDs; CD-Rs require physical destruction when discarded. Never run
  a generic wipe command against a machine with valuable keys.
- With only three selected CDs and the public recovery information, repeat on
  a fresh verified offline installation. Do not consult original wallet files.
  Recover balances on a separate watch coordinator, sign, finalize, broadcast,
  and confirm another test spend. Repeat with alternate triples.
- Record failures, exact Core version, hardware, disc models, restoration and
  transaction results. Retain public evidence without exposing private keys.

## Airgap and hardware acceptance

- Before generating non-test keys, verify that Ethernet is unplugged and radio
  hardware is removed/disabled. Firmware settings alone may be reversible.
- Confirm `/etc/glacier2/enforce --check` succeeds, loopback works, every other
  link is down, radios are blocked, routes cannot carry traffic, and Core reports
  `networkactive=false` and zero connections. Confirm
  `/proc/sys/kernel/modules_disabled` is `1` during the generation session.
- Reboot a **test** installation; inspect `systemctl status glacier2-airgap`,
  kernel boot parameters, masked services, module blacklists, firewall rules and
  interface states. Repeat the check after sleep/resume if it will ever be used.
- On disposable test hardware only, test hotplug NICs and attempts by ordinary
  services to reconnect. Confirm IPv4 and IPv6 isolation while RPC on loopback
  still works. Treat any unexpected connection or enforcement failure as failure.
- Test interrupted download, invalid signatures, occupied RPC port, existing
  state, failed import, wrong/used disc, read error and interrupted burn. Confirm
  later stages do not run and that existing keys are never regenerated.

## Partial-run recovery

The runner intentionally refuses reruns after it creates state. Preserve
`/var/lib/glacier2`, all discs, and the source. Inspect completion records but
verify actual wallets and disc hashes; a marker is not proof. If keys exist, do
not delete state to obtain a clean run. Review with the machine offline and make
additional `backupwallet` copies from the existing wallets to new blank media.
Some discs may already be valid even when the run failed later. Failed or partly
written CDs are never reused automatically. There is no automatic resume mode.

Never reconnect the original signing machine. For restoring normal computer use,
first complete backup recovery and then sanitize/reinstall the machine. Keep the
seven signer CDs in separate protected locations, retain the full public policy,
and schedule periodic readability and recovery checks. This prototype does not
provide independent seven-device key generation, wallet encryption, automated
spending, secure erase, or a complete audited operational security procedure.
