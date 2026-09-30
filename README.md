# Glacier-2

**A minimal single-signature Bitcoin Core cold-storage appliance with threshold paper recovery.**

Glacier-2 turns a clean Ubuntu computer into a permanently offline Bitcoin signing
machine. It installs and verifies Bitcoin Core, applies persistent network
isolation, creates one encrypted native-SegWit descriptor wallet, and backs up the
wallet's 256-bit master secret using Blockchain Commons **bc-shamir + Bytewords**.

> [!WARNING]
> Glacier-2 is experimental and has not received an independent audit as a complete
> system. Do not use meaningful funds until you have reviewed the source and completed
> the destructive recovery test in [RECOVERY.md](RECOVERY.md).

## What you get

- one encrypted Bitcoin Core **single-sig BIP84** signer wallet;
- one public watch-only wallet producing standard `bc1q...` addresses;
- a public descriptor/manifest for independent address verification;
- an encrypted `wallet.dat` recovery copy;
- handwritten threshold shares in one of these policies:
  - **2 of 3**
  - **3 of 5**
  - **3 of 7**

The shares are the ultimate recovery material. Any threshold set reconstructs the
same 32-byte master secret. From that secret Glacier-2 deterministically reconstructs:

1. the BIP32 master extended private key used by Bitcoin Core; and
2. the high-entropy passphrase protecting the encrypted Core wallet.

The Core passphrase is never intended to be written down or shown to the user.

## Backup format

Glacier-2 does **not** use BIP39 seed words. Each Shamir share is encoded with
Blockchain Commons Bytewords as a line of ordinary four-letter words with a CRC32
checksum. The share record also includes a random set identifier, threshold, share
count, and share number so shares from different wallets cannot be silently mixed.

Bytewords provides transcription **error detection**, not encryption or automatic
error correction.

During setup each share is shown by itself. You write it down, the screen and
terminal scrollback are cleared, and you must type the written copy back correctly.
After all shares are verified Glacier-2 reconstructs the master secret from every
possible threshold combination before accepting the backup.

No Bytewords share text is intentionally written to disk by Glacier-2.

## Setup

Use a dedicated computer with a clean Ubuntu Desktop 24.04 or 26.04 installation.
Enable full-disk encryption during Ubuntu installation. Physically disconnect or
remove network/radio hardware when practical.

Internet access is required only before the air-gap stage so Glacier-2 can:

- download and cryptographically verify the pinned Bitcoin Core build;
- fetch exact pinned Blockchain Commons source commits;
- compile and self-test the small Shamir/Bytewords helper.

Then run from a reviewed checkout:

```bash
sudo bash setup.sh
```

Glacier-2 will:

1. verify and install Bitcoin Core 32.0rc2;
2. build the Shamir helper from exact pinned upstream commits;
3. disable networking and apply persistent air-gap rules;
4. ask you to choose 2-of-3, 3-of-5, or 3-of-7;
5. generate a 32-byte master secret using the Linux CSPRNG;
6. create one encrypted Core descriptor wallet from that secret;
7. create standard BIP84 receive/change descriptors using Bitcoin Core itself;
8. create a watch-only wallet with the matching public descriptors;
9. generate, display, and verify every written Bytewords share;
10. verify every threshold combination reconstructs the exact master secret;
11. save an encrypted `wallet.dat` convenience backup and public manifest.

Once the air-gap stage begins, do not reconnect the machine to a network.

### Development test mode

```bash
sudo bash setup.sh --test
```

This still performs real hardening and creates real keys, but uses a 2-of-3 policy
without the manual share-transcription ceremony. It does **not** leave a usable
paper backup. Never fund a test-mode installation.

## Normal use

The desktop launcher opens only the watch-only wallet in production. The private
signer remains in the root-owned offline Core datadir and remains encrypted.

When signing is required, recover the threshold secret from the written shares and
unlock the signer locally. The recovery utility derives the Core passphrase
internally; it does not print it.

The encrypted recovery wallet is stored at:

```text
/var/lib/glacier2/recovery/wallet.dat
```

You may make redundant copies of this **encrypted** file on ordinary storage. The
written Shamir shares should remain physically separated.

The encrypted file is convenience, not the root backup: the shares alone can
recreate the same wallet and addresses on a clean Bitcoin Core installation.

## Security boundaries

- Use a physically isolated machine when protecting significant value.
- Software network blocking cannot defeat malicious firmware, kernel, or root.
- A compromise during initial key generation can compromise the wallet.
- The Glacier wrapper itself is not independently audited.
- `bc-shamir` has an independent security review; the Bytewords C implementation
  is an encoding layer and upstream labels it pre-production/late-alpha.
- CRC32 detects accidental transcription corruption; it is not authentication.
- Python cannot guarantee that every immutable temporary string containing an xprv
  or derived passphrase is immediately erased from process memory. The process exits
  after setup/recovery and core dumps are disabled, but this is not equivalent to a
  formally verified secret-memory runtime.

Read [TECHNICAL.md](TECHNICAL.md) for the exact construction and
[RECOVERY.md](RECOVERY.md) before funding.
