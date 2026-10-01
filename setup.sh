#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
export LC_ALL=C PATH=/usr/sbin:/usr/bin:/sbin:/bin

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
STATE=/var/lib/glacier2
CORE=$STATE/core
DATA=$STATE/data
DRIVE=${GLACIER_DRIVE:-/dev/sr0}
CORE_PID=

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
rpc() { "$CORE/bin/bitcoin-cli" -datadir="$DATA" -chain=main -rpcport=18459 "$@"; }

stop_core() {
    [[ -n $CORE_PID ]] || return 0
    rpc stop >/dev/null 2>&1 || true
    wait "$CORE_PID" 2>/dev/null || true
    CORE_PID=
}

cleanup() {
    status=$?
    trap - EXIT
    stop_core
    exit "$status"
}

start_core() {
    mkdir -p "$DATA"
    "$CORE/bin/bitcoind" -datadir="$DATA" -chain=main -server=1 -daemon=0 \
        -networkactive=0 -listen=0 -discover=0 -dnsseed=0 -fixedseeds=0 \
        -listenonion=0 -natpmp=0 -rpcbind=127.0.0.1 -rpcallowip=127.0.0.1 \
        -rpcport=18459 -debuglogfile=0 -printtoconsole=0 &
    CORE_PID=$!
    rpc -rpcwait -rpcwaittimeout=60 getnetworkinfo |
        python3 -c 'import json,sys; x=json.load(sys.stdin); assert not x["networkactive"] and x["connections"]==0'
}

install_core() {
    [[ $(uname -m) == x86_64 ]] || die 'x86-64 only.'
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends nftables rfkill xorriso eject
    mkdir -p "$CORE"
    tar -xzf "$ROOT/vendor/bitcoin-32.0rc2-x86_64-linux-gnu.tar.gz" \
        --strip-components=1 --no-same-owner -C "$CORE"
    "$CORE/bin/bitcoind" --version | head -n1 | grep -q 'v32.0.0rc2' || die 'Wrong Bitcoin Core version.'
    for module in sr_mod sg rfkill nf_tables; do modprobe "$module"; done
}

write_airgap() {
    mkdir -p /etc/glacier2

    cat >/etc/glacier2/airgap.nft <<'EOF'
table inet glacier2 {
 chain input { type filter hook input priority -300; policy drop; iifname "lo" accept }
 chain output { type filter hook output priority -300; policy drop; oifname "lo" accept }
 chain forward { type filter hook forward priority -300; policy drop; }
}
EOF

    cat >/etc/glacier2/enforce <<'EOF'
#!/bin/bash
set -e
PATH=/usr/sbin:/usr/bin:/sbin:/bin
nft list table inet glacier2 >/dev/null 2>&1 || nft -f /etc/glacier2/airgap.nft
rfkill block all
for path in /sys/class/net/*; do
    dev=${path##*/}
    [[ $dev == lo ]] || { ip addr flush dev "$dev"; ip -6 addr flush dev "$dev"; ip link set "$dev" down; }
done
ip link set lo up
swapoff -a
sysctl -w kernel.modules_disabled=1 >/dev/null
EOF
    chmod 700 /etc/glacier2/enforce

    cat >/etc/systemd/system/glacier2-airgap.service <<'EOF'
[Unit]
Description=Glacier-2 airgap
DefaultDependencies=no
After=local-fs.target systemd-modules-load.service
Before=network-pre.target
[Service]
Type=oneshot
ExecStart=/etc/glacier2/enforce
RemainAfterExit=yes
[Install]
WantedBy=sysinit.target
EOF
}

airgap() {
    write_airgap
    for service in NetworkManager systemd-networkd wpa_supplicant bluetooth ModemManager; do
        systemctl mask --now "$service" >/dev/null
    done
    systemctl daemon-reload
    systemctl enable glacier2-airgap.service >/dev/null
    /etc/glacier2/enforce
    [[ $(cat /proc/sys/kernel/modules_disabled) == 1 ]] || die 'Module lock failed.'
    nft list table inet glacier2 >/dev/null || die 'Firewall failed.'
}

make_wallet() {
    start_core
    python3 "$ROOT/wallets.py" "$CORE/bin/bitcoin-cli" "$DATA" main "$STATE/descriptors.txt"
}

burn_cds() {
    local n dir iso sectors
    mkdir "$STATE/discs"

    for n in {1..7}; do
        dir=$STATE/discs/$n
        iso=$STATE/discs/$n.iso
        mkdir "$dir"
        rpc -rpcwallet="signer_$n" backupwallet "$dir/wallet.dat"
        cp "$STATE/descriptors.txt" "$ROOT/RECOVERY.md" "$dir/"
        printf 'Glacier-2 signer %s of 7\nUNENCRYPTED PRIVATE BACKUP\n' "$n" >"$dir/DISC.txt"
        (cd "$dir" && sha256sum wallet.dat descriptors.txt RECOVERY.md DISC.txt >SHA256SUMS)
        xorriso -as mkisofs -quiet -R -J -V "GLACIER2_S$n" -o "$iso" "$dir"

        printf 'Insert blank CD-R for signer %s, then press Enter: ' "$n" >/dev/tty
        read -r </dev/tty
        findmnt -rn -S "$DRIVE" >/dev/null && die 'Disc is mounted.'
        xorriso -outdev "$DRIVE" -toc >"$STATE/discs/media.log" 2>&1
        grep -Eq 'Media current:.*CD-R[[:space:]]*$' "$STATE/discs/media.log" || die 'Not a CD-R.'
        grep -q 'Media status : is blank' "$STATE/discs/media.log" || die 'Disc is not blank.'
        xorriso -as cdrecord -v dev="$DRIVE" -dao "$iso"
        sync
        eject "$DRIVE"

        printf 'Reinsert signer %s, unmount it if needed, then press Enter: ' "$n" >/dev/tty
        read -r </dev/tty
        findmnt -rn -S "$DRIVE" >/dev/null && die 'Disc is mounted.'
        sectors=$(( $(stat -c %s "$iso") / 2048 ))
        cmp "$iso" <(dd if="$DRIVE" bs=2048 count="$sectors" iflag=fullblock status=none)
        eject "$DRIVE"
        printf 'Signer %s verified. Label it and store it separately.\n' "$n"
    done
}

main() {
    [[ $# == 0 ]] || die 'No command-line options.'
    [[ $EUID == 0 ]] || die 'Run with sudo on clean Ubuntu.'
    [[ -z ${SSH_CONNECTION:-} ]] || die 'Do not run over SSH.'
    [[ ! -e $STATE ]] || die 'Existing Glacier state; refusing to regenerate.'
    [[ -b $DRIVE ]] || die "Optical drive not found: $DRIVE"

    mkdir -m 700 "$STATE"
    trap cleanup EXIT
    install_core
    airgap
    make_wallet
    burn_cds
    printf 'Done. Keep the machine offline.\n'
}

[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
