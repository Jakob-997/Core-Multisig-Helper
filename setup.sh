#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATE=/var/lib/glacier2
CORE=$STATE/core
DATA=$STATE/data
DRIVE=${GLACIER_DRIVE:-/dev/sr0}

die(){ echo "ERROR: $*" >&2; exit 1; }
rpc(){ "$CORE/bin/bitcoin-cli" -datadir="$DATA" -rpcport=18459 "$@"; }
call(){
    local wallet=$1 method=$2
    shift 2
    if [[ $wallet ]]; then
        printf '%s\n' "$@" | rpc -rpcwallet="$wallet" -stdin "$method"
    else
        printf '%s\n' "$@" | rpc -stdin "$method"
    fi
}

airgap(){
    systemctl stop NetworkManager
    rfkill block all
    nft -f - <<'EOF'
table inet glacier2 {
 chain input { type filter hook input priority -300; policy drop; iifname "lo" accept }
 chain output { type filter hook output priority -300; policy drop; oifname "lo" accept }
 chain forward { type filter hook forward priority -300; policy drop; }
}
EOF
}

install_core(){
    mkdir "$CORE"
    tar -xzf "$ROOT/bitcoin-core.tar.gz" --strip-components=1 -C "$CORE"
    mkdir "$DATA"
    "$CORE/bin/bitcoind" -datadir="$DATA" -server -daemonwait -networkactive=0 -listen=0 -rpcport=18459 -debuglogfile=0
    trap 'rpc stop >/dev/null 2>&1 || true' EXIT
}

make_wallet(){
    local n b wallet root account private checksum request
    local path=m/87h/0h/0h
    local -a roots origins xpubs raw public

    for n in {1..7}; do
        wallet=signer_$n
        call "" createwallet "$wallet" false true >/dev/null
        root=$(rpc -rpcwallet="$wallet" addhdkey | jq -r .xpub)
        account=$(call "$wallet" derivehdkey "$path" "{\"hdkey\":\"$root\"}")
        roots[n]=$root
        origins[n]=$(jq -r .origin <<<"$account")
        xpubs[n]=$(jq -r .xpub <<<"$account")
    done

    for b in 0 1; do
        raw[b]='wsh(sortedmulti(3'
        for n in {1..7}; do raw[b]+=",${origins[n]}${xpubs[n]}/$b/*"; done
        raw[b]+='))'
        checksum=$(call "" getdescriptorinfo "${raw[b]}" | jq -r .checksum)
        public[b]="${raw[b]}#$checksum"
    done
    printf '%s\n%s\n' "${public[0]}" "${public[1]}" >"$STATE/descriptors.txt"

    for n in {1..7}; do
        wallet=signer_$n
        account=$(call "$wallet" derivehdkey "$path" "{\"hdkey\":\"${roots[n]}\",\"private\":true}")
        private=$(jq -r .xprv <<<"$account")
        for b in 0 1; do
            account="${raw[b]/${xpubs[n]}/$private}"
            checksum=$(call "" getdescriptorinfo "$account" | jq -r .checksum)
            [[ $b == 0 ]] && receive="$account#$checksum" || change="$account#$checksum"
        done
        request="[{\"desc\":\"$receive\",\"active\":true,\"internal\":false,\"timestamp\":\"now\",\"range\":[0,999]},{\"desc\":\"$change\",\"active\":true,\"internal\":true,\"timestamp\":\"now\",\"range\":[0,999]}]"
        call "$wallet" importdescriptors "$request" >/dev/null
    done
}

burn_cds(){
    local n dir iso sectors toc
    mkdir "$STATE/discs"
    for n in {1..7}; do
        dir=$STATE/discs/$n
        iso=$STATE/discs/$n.iso
        mkdir "$dir"
        rpc -rpcwallet="signer_$n" backupwallet "$dir/wallet.dat"
        cp "$STATE/descriptors.txt" "$dir/"
        (cd "$dir" && sha256sum wallet.dat descriptors.txt >SHA256SUMS)
        xorriso -as mkisofs -quiet -R -J -V "GLACIER2_S$n" -o "$iso" "$dir"

        read -rp "Insert blank CD-R for signer $n, then press Enter: " </dev/tty
        toc=$(xorriso -outdev "$DRIVE" -toc 2>&1)
        grep -q 'Media current:.*CD-R' <<<"$toc" || die 'Not a CD-R.'
        grep -q 'Media status : is blank' <<<"$toc" || die 'Disc is not blank.'
        xorriso -as cdrecord -v dev="$DRIVE" -dao "$iso"
        eject "$DRIVE"

        read -rp "Reinsert signer $n, then press Enter: " </dev/tty
        sectors=$(( $(stat -c %s "$iso") / 2048 ))
        cmp "$iso" <(dd if="$DRIVE" bs=2048 count="$sectors" status=none)
        eject "$DRIVE"
        echo "Signer $n verified. Label and store it separately."
    done
}

[[ $EUID == 0 ]] || die 'Run with sudo.'
[[ $# == 0 ]] || die 'No arguments.'
[[ ! -e $STATE ]] || die 'Existing Glacier wallet.'
[[ -b $DRIVE ]] || die "No optical drive: $DRIVE"
for command in nft rfkill xorriso eject jq; do command -v "$command" >/dev/null || die "Install $command first."; done

mkdir -m 700 "$STATE"
airgap
install_core
make_wallet
burn_cds
rpc stop
trap - EXIT
echo 'Done. Keep the machine offline.'
