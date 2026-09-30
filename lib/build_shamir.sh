#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
export LC_ALL=C
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

[[ $# -ge 1 && $# -le 2 ]] || { printf 'Usage: build_shamir.sh OUTPUT [PROVENANCE_FILE]\n' >&2; exit 2; }
OUTPUT=$1
PROVENANCE=${2:-}
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

BC_SHAMIR_COMMIT=61de3426318b22de21b5421db642fa390d51f740
BC_CRYPTO_COMMIT=6307acbc07bdc649a577f78e2ccae36c96bf9fa9
BC_BYTEWORDS_COMMIT=c32d8b59690b90f60d26696c955edfecf7e22237

for cmd in git cc mktemp sha256sum; do command -v "$cmd" >/dev/null || { printf 'Missing command: %s\n' "$cmd" >&2; exit 1; }; done

work=$(mktemp -d)
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT

fetch_exact() {
    local url=$1 commit=$2 destination=$3 actual
    git clone -q --no-tags "$url" "$destination"
    git -C "$destination" checkout -q --detach "$commit"
    actual=$(git -C "$destination" rev-parse HEAD)
    [[ $actual == "$commit" ]] || { printf 'Pinned dependency commit mismatch.\n' >&2; exit 1; }
}

fetch_exact https://github.com/BlockchainCommons/bc-crypto-base.git "$BC_CRYPTO_COMMIT" "$work/crypto"
fetch_exact https://github.com/BlockchainCommons/bc-shamir.git "$BC_SHAMIR_COMMIT" "$work/shamir"
fetch_exact https://github.com/BlockchainCommons/bc-bytewords.git "$BC_BYTEWORDS_COMMIT" "$work/bytewords"

mkdir -p "$work/include/bc-crypto-base"
cp "$work/crypto/src/"*.h "$work/include/bc-crypto-base/"

tmp="$OUTPUT.tmp.$$"
mkdir -p "$(dirname -- "$OUTPUT")"
trap 'rm -f -- "$tmp"; cleanup' EXIT
cc -std=c11 -O2 -Wall -Wextra -Wpedantic \
    -fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE -pie \
    -Wl,-z,relro,-z,now -Wl,-z,noexecstack \
    -I"$work/include" -I"$work/shamir/src" -I"$work/bytewords/src" \
    "$ROOT/shamir_helper.c" \
    "$work/shamir/src/shamir.c" "$work/shamir/src/interpolate.c" "$work/shamir/src/hazmat.c" \
    "$work/crypto/src/hmac.c" "$work/crypto/src/sha2.c" "$work/crypto/src/memzero.c" "$work/crypto/src/crc32.c" \
    "$work/bytewords/src/bc-bytewords.c" \
    -o "$tmp"

"$tmp" selftest | grep -Fx 'OK' >/dev/null
chmod 0755 "$tmp"
mv -f -- "$tmp" "$OUTPUT"

if [[ -n $PROVENANCE ]]; then
    cat >"$PROVENANCE" <<EOF
bc-shamir $BC_SHAMIR_COMMIT
bc-crypto-base $BC_CRYPTO_COMMIT
bc-bytewords $BC_BYTEWORDS_COMMIT
helper-sha256 $(sha256sum "$OUTPUT" | awk '{print $1}')
EOF
    chmod 0600 "$PROVENANCE"
fi
