# Glacier-2 technical reference

## Architecture

Glacier-2 intentionally keeps the cryptographic design small:

```text
Linux getrandom()
      |
      v
32-byte uniformly random master secret
      |
      +--> BIP32 master xprv --> Bitcoin Core addhdkey
      |                              |
      |                              +--> createwalletdescriptor("bech32")
      |                                   BIP84 wpkh receive/change descriptors
      |
      +--> HMAC-SHA256("Glacier-2 Core wallet encryption v1")
      |        |
      |        +--> 64-character Core wallet passphrase
      |
      +--> bc-shamir --> threshold binary shares
                            |
                            +--> Glacier share metadata
                                    |
                                    +--> Bytewords + CRC32
```

The wallet passphrase is **domain separated** from the BIP32 derivation. It is not
the master secret rendered as text.

## Bitcoin wallet

The signer is a blank encrypted Bitcoin Core descriptor wallet. Glacier-2 imports
one deterministic master xprv with `addhdkey` and then asks Bitcoin Core itself to
create `bech32` wallet descriptors.

For mainnet Core therefore constructs standard BIP84 single-signature paths:

```text
m/84'/0'/0'/0/*   receive
m/84'/0'/0'/1/*   change
```

Glacier-2 does not implement child-key derivation or address generation itself.
The watch-only wallet imports the public descriptor pair and contains no private
keys.

## Master-secret derivations

The 32-byte master secret is generated with the Linux kernel CSPRNG.

The BIP32 master node is the standard BIP32 operation:

```text
I = HMAC-SHA512(key="Bitcoin seed", data=master_secret)
master private key = IL
master chain code  = IR
```

Glacier-2 contains only the small master-xprv serialization step. Bitcoin Core does
all subsequent wallet derivation.

The encrypted-wallet passphrase is:

```text
hex(HMAC-SHA256(
    key  = master_secret,
    data = "Glacier-2 Core wallet encryption v1"
))
```

It has 256 bits of source entropy and is never intended for manual transcription.

## Shamir implementation

The helper is compiled before air-gapping from exact pinned commits:

- `BlockchainCommons/bc-shamir`
  `61de3426318b22de21b5421db642fa390d51f740` (0.4.0)
- `BlockchainCommons/bc-crypto-base`
  `6307acbc07bdc649a577f78e2ccae36c96bf9fa9`
- `BlockchainCommons/bc-bytewords`
  `c32d8b59690b90f60d26696c955edfecf7e22237`

The build script checks every checked-out HEAD against its pinned commit and runs an
internal Shamir + published Bytewords-vector self-test before installation.

Blockchain Commons' bc-shamir 0.4.0-era code was independently reviewed by
Radically Open Security. Its Shamir construction includes a four-byte integrity
digest. With threshold-minus-one shares this provides an offline verification oracle
that can reduce brute-force work by about 32 bits. Because Glacier-2 shares a
uniformly random 256-bit secret, the resulting brute-force margin remains roughly
224 bits.

## Share record

Each binary share record before Bytewords encoding is:

```text
2 bytes   "SS"
1 byte    format version = 1
8 bytes   random set identifier
1 byte    threshold
1 byte    share count
1 byte    zero-based share index
32 bytes  bc-shamir share
```

Bytewords appends its CRC32 checksum and maps the result to four-letter words.

The set ID and policy metadata prevent accidental cross-wallet mixing. On recovery
the helper rejects:

- a bad Bytewords checksum;
- unsupported thresholds;
- mismatched set IDs;
- mismatched threshold/share counts;
- duplicate shares;
- an invalid reconstructed bc-shamir integrity digest.

CRC32 is for accidental transcription errors only.

## Backup verification

For each generated share the operator must re-enter the written copy. Glacier-2
accepts it only if the canonicalized words exactly match the generated share and the
Bytewords checksum/metadata validate.

Afterward the software reconstructs the 32-byte master secret from **every**
threshold-sized combination:

- 2-of-3: 3 combinations
- 3-of-5: 10 combinations
- 3-of-7: 35 combinations

Any mismatch aborts setup.

## Encrypted wallet backup

`/var/lib/glacier2/recovery/wallet.dat` is created with Core's `backupwallet`
after the signer has been locked. It is encrypted by Bitcoin Core using the
deterministically derived high-entropy passphrase.

This file may be copied redundantly. It is not necessary for ultimate recovery,
because the threshold shares recreate the exact BIP32 master root and therefore the
same descriptors.

## Software provenance

Bitcoin Core 32.0rc2 is downloaded from the official Bitcoin Core distribution
site. The installer verifies the selected archive hash against `SHA256SUMS` and
requires valid signatures from the two pinned primary fingerprints already recorded
in `modules/install_core.sh`.

The Blockchain Commons helper dependencies are content-pinned Git commits, not
moving branches.

This is verification of downloaded artifacts and pinned source, **not an independent
reproducible build of Bitcoin Core or Blockchain Commons**.

## Air gap

The existing Glacier network hardening remains: nftables drops non-loopback
IPv4/IPv6 traffic, radios are rfkill-blocked, common network services are masked,
network interfaces are flushed/downed/unbound, installed network/radio kernel
drivers are blacklisted, GRUB/initramfs are updated, and module loading is locked
for the running kernel.

Bitcoin Core additionally runs with networking disabled.

This remains defense in depth. Physical disconnection/removal of network and radio
hardware is stronger.

## Memory limits

The C Shamir helper zeroes secret buffers and disables core dumps. The Python layer
uses a mutable `bytearray` for the master secret and overwrites it on exit.

Python strings returned for the xprv and wallet passphrase are immutable; Python
does not provide a reliable guarantee that their backing memory is immediately
zeroed. They are kept only for the short wallet-creation/recovery operation and are
not written to Glacier files, but this is a real limitation of the prototype.
