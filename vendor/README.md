# Vendored Bitcoin Core

Glacier-2 treats Bitcoin Core as part of the reviewed Glacier release rather than
re-authenticating it during every installation.

The repository contains the official Bitcoin Core **32.0rc2** Linux release archive
for each supported architecture:

- `bitcoin-32.0rc2-x86_64-linux-gnu.tar.gz`
- `bitcoin-32.0rc2-aarch64-linux-gnu.tar.gz`

The expected upstream SHA256 values are recorded in `SHA256SUMS`. They match the
reproducible Guix build attestations published by multiple Bitcoin Core builders for
32.0rc2.

## Trust model

The setup program does **not** download Core, fetch signing keys, or verify upstream
GPG signatures. Reviewing/trusting a specific Glacier-2 commit means trusting the
Bitcoin Core archive committed in that same revision.

Before changing the bundled Core version, the maintainer should independently:

1. download the intended release from the official Bitcoin Core distribution;
2. verify the release checksums/signatures according to Bitcoin Core's release
   verification procedure;
3. compare the artifact with reproducible-build attestations where available;
4. replace the archive and `SHA256SUMS` together;
5. review and test the Glacier release before tagging it.

A reviewer can independently hash the committed archives at any time with:

```bash
cd vendor
sha256sum -c SHA256SUMS
```
