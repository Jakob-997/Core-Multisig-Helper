#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
export QT_QPA_PLATFORM=xcb
[[ $EUID != 0 ]] || { printf 'Launch from your desktop account, not root.\n' >&2; exit 1; }
base=$HOME/.local/share/glacier2
chain=$(cat "$base/chain")
[[ $chain == main || $chain == regtest || $chain == signet ]] || exit 1
mode=$(cat "$base/desktop-mode" 2>/dev/null || printf 'watch-only\n')
[[ $mode == watch-only || $mode == test-signers ]] || exit 1
wallet_args=(-wallet=watch_only)
if [[ $mode == test-signers ]]; then
    for n in {1..7}; do
        wallet_args+=("-wallet=signer_$n")
    done
fi
exec /opt/glacier2/core/bin/bitcoin-qt -datadir="$base/core" -chain="$chain" \
    "${wallet_args[@]}" -networkactive=0 -listen=0 -discover=0 -dnsseed=0 \
    -fixedseeds=0 -listenonion=0 -natpmp=0 -server=0
