#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
export QT_QPA_PLATFORM=xcb
[[ $EUID != 0 ]] || { printf 'Launch from your desktop account, not root.\n' >&2; exit 1; }
base=$HOME/.local/share/glacier2
chain=$(cat "$base/chain")
[[ $chain == main || $chain == regtest || $chain == signet ]] || exit 1
exec /opt/glacier2/core/bin/bitcoin-qt -datadir="$base/core" -chain="$chain" \
    -wallet=watch_only -networkactive=0 -listen=0 -discover=0 -dnsseed=0 \
    -fixedseeds=0 -listenonion=0 -natpmp=0 -server=0
