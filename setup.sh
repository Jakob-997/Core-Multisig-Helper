#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077

cd "$(dirname "${BASH_SOURCE[0]}")"
STATE=/var/lib/glacier2
CORE=$STATE/core
DATA=$STATE/data
DRIVE=/dev/sr0

die(){ echo "ERROR: $*" >&2; exit 1; }
rpc(){ "$CORE/bin/bitcoin-cli" -datadir="$DATA" -rpcport=18459 "$@"; }
node(){ local m=$1; shift; printf '%s\n' "$@" | rpc -stdin "$m"; }
wallet(){ local w=$1 m=$2; shift 2; printf '%s\n' "$@" | rpc -rpcwallet="$w" -stdin "$m"; }

airgap(){
    cat >/etc/nftables.conf <<'EOF'
flush ruleset
table inet glacier2 {
 chain input { type filter hook input priority -300; policy drop; iifname "lo" accept; }
 chain output { type filter hook output priority -300; policy drop; oifname "lo" accept; }
}
EOF
    cat >/etc/systemd/system/glacier-airgap.service <<'EOF'
[Unit]
Description=Glacier permanent airgap
Wants=network-pre.target
Before=network-pre.target
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'rfkill block all 2>/dev/null || true; for i in /sys/class/net/*; do n=${i##*/}; [ "$n" = lo ] || ip link set "$n" down 2>/dev/null || true; done'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    systemctl mask --now NetworkManager.service NetworkManager-wait-online.service systemd-networkd.service systemd-networkd-wait-online.service networking.service wpa_supplicant.service wpa_supplicant@.service iwd.service ModemManager.service 2>/dev/null || true
    systemctl daemon-reload
    systemctl enable --now glacier-airgap.service nftables.service
}

install_core(){
    mkdir "$CORE" "$DATA"
    tar -xzf bitcoin-core.tar.gz --strip-components=1 -C "$CORE"
    "$CORE/bin/bitcoind" -datadir="$DATA" -daemonwait -networkactive=0 -listen=0 -rpcport=18459
    trap 'rpc stop >/dev/null 2>&1 || true' EXIT
}

make_wallet(){
    local i w root account raw private checksum request
    local -a origin xpub xprv

    for ((i=1;i<=N;i++)); do
        w=signer_$i
        node createwallet "$w" false true >/dev/null
        root=$(rpc -rpcwallet="$w" addhdkey | jq -r .xpub)
        account=$(wallet "$w" derivehdkey m/87h/0h/0h "{\"hdkey\":\"$root\",\"private\":true}")
        origin[i]=$(jq -r .origin <<<"$account")
        xpub[i]=$(jq -r .xpub <<<"$account")
        xprv[i]=$(jq -r .xprv <<<"$account")
    done

    raw="wsh(sortedmulti($M"
    for ((i=1;i<=N;i++)); do raw+=",${origin[i]}${xpub[i]}/<0;1>/*"; done
    raw+='))'
    account=$(node getdescriptorinfo "$raw")
    [[ $(jq '.multipath_expansion|length' <<<"$account") == 2 ]] || die 'Bad descriptor.'
    checksum=$(jq -r .checksum <<<"$account")
    echo "$raw#$checksum" >"$STATE/descriptors.txt"
    node createwallet watch_only true true >/dev/null
    request=$(jq -cn --arg desc "$raw#$checksum" '[{desc:$desc,active:true,timestamp:"now",range:[0,999]}]')
    wallet watch_only importdescriptors "$request" >/dev/null
    [[ $(rpc -rpcwallet=watch_only getwalletinfo | jq -r .private_keys_enabled) == false ]] || die 'WATCH ONLY contains private keys.'

    for ((i=1;i<=N;i++)); do
        private="${raw/${xpub[i]}/${xprv[i]}}"
        checksum=$(node getdescriptorinfo "$private" | jq -r .checksum)
        request=$(jq -cn --arg desc "$private#$checksum" '[{desc:$desc,active:true,timestamp:"now",range:[0,999]}]')
        wallet "signer_$i" importdescriptors "$request" >/dev/null
    done
}

burn_cds(){
    local i iso sectors
    mkdir "$STATE/cd"
    cp "$STATE/descriptors.txt" "$STATE/cd/"
    rpc -rpcwallet=watch_only backupwallet "$STATE/cd/watch_only.dat"
    iso=$STATE/watch_only.iso
    xorriso -as mkisofs -quiet -R -J -o "$iso" "$STATE/cd"
    read -rp "Insert blank CD-R for WATCH ONLY, then press Enter: " </dev/tty
    xorriso -as cdrecord -v dev="$DRIVE" -dao "$iso"
    eject "$DRIVE"
    read -rp "Reinsert WATCH ONLY, then press Enter: " </dev/tty
    sectors=$(( $(stat -c %s "$iso") / 2048 ))
    cmp "$iso" <(dd if="$DRIVE" bs=2048 count="$sectors" status=none)
    eject "$DRIVE"
    echo "WATCH ONLY verified. Use this disc on the online computer."
    rm "$STATE/cd/watch_only.dat"
    for ((i=1;i<=N;i++)); do
        rm -f "$STATE/cd/wallet.dat"
        rpc -rpcwallet="signer_$i" backupwallet "$STATE/cd/wallet.dat"
        iso=$STATE/signer_$i.iso
        xorriso -as mkisofs -quiet -R -J -o "$iso" "$STATE/cd"
        read -rp "Insert blank CD-R for signer $i, then press Enter: " </dev/tty
        xorriso -as cdrecord -v dev="$DRIVE" -dao "$iso"
        eject "$DRIVE"
        read -rp "Reinsert signer $i, then press Enter: " </dev/tty
        sectors=$(( $(stat -c %s "$iso") / 2048 ))
        cmp "$iso" <(dd if="$DRIVE" bs=2048 count="$sectors" status=none)
        eject "$DRIVE"
        echo "Signer $i verified. Label and store it separately."
    done
}

read -rp 'Generate keys or spend? [generate]: ' MODE </dev/tty; MODE=${MODE:-generate}
[[ $MODE == generate || $MODE == spend ]] || die 'Enter generate or spend.'
[[ ! -e $STATE ]] || die 'Existing Glacier state.'
for c in nft rfkill ip systemctl; do command -v "$c" >/dev/null || die "Missing $c."; done

if [[ $MODE == generate ]]; then
    read -rp 'Select m-n [default 3-7]: ' MN </dev/tty; MN=${MN:-3-7}
    MN=${MN//-of-/-}; MN=${MN// of /-}; M=${MN%-*}; N=${MN#*-}
    [[ $M =~ ^[1-9][0-9]*$ && $N =~ ^[1-9][0-9]*$ && $M -le $N && $N -ge 2 && $N -le 20 ]] || die 'Enter m-n, for example 2-5.'
    [[ -b $DRIVE ]] || die "No optical drive: $DRIVE"
    command -v dpkg >/dev/null || die 'Missing dpkg.'
fi

airgap
[[ $MODE == generate ]] && dpkg -i packages/*.deb >/dev/null
[[ $MODE == generate ]] && for c in xorriso eject jq; do command -v "$c" >/dev/null || die "Missing $c."; done
mkdir -m 700 "$STATE"
install_core
[[ $MODE == spend ]] && { echo "Bitcoin Core is ready in $CORE/bin."; exit; }
make_wallet
burn_cds
rpc stop
trap - EXIT
echo 'Done. Keep the machine offline.'
