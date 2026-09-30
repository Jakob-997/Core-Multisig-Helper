#!/usr/bin/env bash
# Sourced only by the runner; never enable shell tracing around wallet operations.
set -Eeuo pipefail
set +x
umask 077
export LC_ALL=C
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
need() { command -v "$1" >/dev/null || die "Missing command: $1"; }
confirm() {
    local answer
    printf '%s\nType %s: ' "$1" "$2" >/dev/tty
    read -r answer </dev/tty
    [[ $answer == "$2" ]] || die 'Confirmation did not match.'
}
rpc() { "$CORE/bin/bitcoin-cli" -datadir="$DATA" -chain="$CHAIN" -rpcport=18459 "$@"; }
stop_core() {
    if [[ ${CORE_STARTED:-0} == 1 ]]; then
        rpc stop >/dev/null 2>&1 || true
        if [[ -n ${CORE_PID:-} ]]; then wait "$CORE_PID" || true; fi
    fi
}
cleanup() {
    local status=$?
    trap - EXIT
    stop_core
    if (( status != 0 )); then
        log 'Stopped after failure. Any applied airgap restrictions remain. Preserve all state; never regenerate over it.'
    fi
    exit "$status"
}
start_core() {
    [[ ! -e $DATA/bitcoin.conf ]] || die 'Unexpected bitcoin.conf in dedicated data directory.'
    mkdir -p "$DATA"
    "$CORE/bin/bitcoind" -datadir="$DATA" -chain="$CHAIN" -server=1 \
        -listen=0 -discover=0 -dnsseed=0 -fixedseeds=0 -networkactive=0 \
        -listenonion=0 -natpmp=0 -rpcbind=127.0.0.1 \
        -rpcallowip=127.0.0.1 -rpcport=18459 -debuglogfile=0 \
        -printtoconsole=0 -daemon=0 &
    CORE_PID=$!
    CORE_STARTED=1
    local ready=0
    for ((i=0; i<60; i++)); do
        if "$CORE/bin/bitcoin-cli" -datadir="$DATA" -chain="$CHAIN" -rpcport=18459 getnetworkinfo >/dev/null 2>&1; then ready=1; break; fi
        kill -0 "$CORE_PID" 2>/dev/null || die 'Core exited during startup.'
        sleep 1
    done
    (( ready == 1 )) || die 'Core startup timed out.'
    rpc getnetworkinfo | jq -e '.networkactive == false and .connections == 0' >/dev/null
    rpc help addhdkey >/dev/null
    rpc help derivehdkey >/dev/null
}
