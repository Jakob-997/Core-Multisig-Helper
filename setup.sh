#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
export LC_ALL=C PATH=/usr/sbin:/usr/bin:/sbin:/bin

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
STATE=/var/lib/glacier2
DATA=$STATE/core-data
CORE=/opt/glacier2/core
ARCHIVE=$ROOT/vendor/bitcoin-32.0rc2-x86_64-linux-gnu.tar.gz
CORE_STARTED=0

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
rpc() { "$CORE/bin/bitcoin-cli" -datadir="$DATA" -chain="$CHAIN" -rpcport=18459 "$@"; }

stop_core() {
    (( CORE_STARTED )) || return
    rpc stop >/dev/null 2>&1 || true
    wait "${CORE_PID:-}" 2>/dev/null || true
    CORE_STARTED=0
}

cleanup() {
    local status=$?
    trap - EXIT
    stop_core
    (( status == 0 )) || log 'Stopped after failure. Preserve the wallet state; do not regenerate over it.'
    exit "$status"
}

start_core() {
    mkdir -p "$DATA"
    "$CORE/bin/bitcoind" -datadir="$DATA" -chain="$CHAIN" -server=1 -daemon=0 \
        -networkactive=0 -listen=0 -discover=0 -dnsseed=0 -fixedseeds=0 \
        -listenonion=0 -natpmp=0 -rpcbind=127.0.0.1 -rpcallowip=127.0.0.1 \
        -rpcport=18459 -debuglogfile=0 -printtoconsole=0 &
    CORE_PID=$!
    CORE_STARTED=1
    for _ in {1..60}; do
        if rpc getnetworkinfo >/dev/null 2>&1; then
            rpc getnetworkinfo | jq -e '.networkactive == false and .connections == 0' >/dev/null
            return
        fi
        kill -0 "$CORE_PID" 2>/dev/null || die 'Bitcoin Core exited during startup.'
        sleep 1
    done
    die 'Bitcoin Core startup timed out.'
}

confirm() {
    local answer
    printf '%s\nType %s: ' "$1" "$2" >/dev/tty
    read -r answer </dev/tty
    [[ $answer == "$2" ]] || die 'Confirmation did not match.'
}

install_core() {
    [[ $(uname -m) == x86_64 ]] || die 'Glacier-2 supports x86-64 PCs only.'
    [[ -f $ARCHIVE ]] || die 'Bundled Bitcoin Core archive is missing.'

    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
    apt-get update
    apt-get install -y --no-install-recommends \
        ca-certificates jq python3 nftables rfkill iproute2 xorriso eject kmod util-linux diffutils

    mkdir -p /opt/glacier2 "$STATE/extracted"
    tar -xzf "$ARCHIVE" --no-same-owner -C "$STATE/extracted"
    [[ -d $STATE/extracted/bitcoin-32.0rc2/bin ]] || die 'Unexpected Bitcoin Core archive.'
    mv "$STATE/extracted/bitcoin-32.0rc2" "$CORE"
    "$CORE/bin/bitcoind" --version | head -n1 | grep -q 'v32.0.0rc2' || die 'Unexpected Bitcoin Core version.'

    modprobe sr_mod
    modprobe sg
    modprobe rfkill
    modprobe nf_tables
    start_core
    stop_core
}

write_airgap_files() {
    install -d -m 700 /etc/glacier2

    cat >/etc/glacier2/airgap.nft <<'EOF'
table inet glacier2 {
    chain input  { type filter hook input  priority -300; policy drop; iifname "lo" accept }
    chain output { type filter hook output priority -300; policy drop; oifname "lo" accept }
    chain forward { type filter hook forward priority -300; policy drop; }
}
EOF

    cat >/etc/glacier2/enforce <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C PATH=/usr/sbin:/usr/bin:/sbin:/bin

if [[ ${1:-} != --check ]]; then
    if [[ $(cat /proc/sys/kernel/modules_disabled) == 0 ]]; then
        modprobe sr_mod
        modprobe sg
        modprobe rfkill
        modprobe nf_tables
    fi
    nft list table inet glacier2 >/dev/null 2>&1 || nft -f /etc/glacier2/airgap.nft
    rfkill block all
    for path in /sys/class/net/*; do
        [[ ${path##*/} == lo ]] && continue
        ip address flush dev "${path##*/}"
        ip -6 address flush dev "${path##*/}"
        ip link set dev "${path##*/}" down
    done
    ip link set lo up
    swapoff -a
    sysctl -w kernel.modules_disabled=1 >/dev/null
fi

[[ $(cat /proc/sys/kernel/modules_disabled) == 1 ]]
for chain in input output forward; do
    nft list chain inet glacier2 "$chain" | grep -q 'policy drop'
done
ip -j link show | python3 -c 'import json,sys; x=json.load(sys.stdin); assert all(i["ifname"]=="lo" or "UP" not in i["flags"] for i in x)'
rfkill --json | python3 -c 'import json,sys; assert all(x["soft"]=="blocked" for x in json.load(sys.stdin).get("rfkilldevices",[]))'
EOF
    chmod 700 /etc/glacier2/enforce

    cat >/etc/systemd/system/glacier2-airgap.service <<'EOF'
[Unit]
Description=Glacier-2 network isolation
DefaultDependencies=no
After=local-fs.target systemd-modules-load.service
Before=network-pre.target network.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/etc/glacier2/enforce
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
EOF
}

airgap() {
    log 'Disabling networking. Physically unplug Ethernet and remove/disable radios when possible.'
    swapoff -a
    write_airgap_files

    for service in NetworkManager NetworkManager-wait-online systemd-networkd systemd-networkd-wait-online \
        systemd-networkd.socket systemd-resolved wpa_supplicant bluetooth ModemManager avahi-daemon \
        avahi-daemon.socket networking connman iwd; do
        systemctl mask --now "$service" >/dev/null
    done

    systemctl daemon-reload
    systemctl enable glacier2-airgap.service >/dev/null
    /etc/glacier2/enforce
    /etc/glacier2/enforce --check
}

make_wallet() {
    /etc/glacier2/enforce --check
    start_core
    python3 "$ROOT/wallets.py" "$CORE/bin/bitcoin-cli" "$DATA" "$CHAIN" "$STATE/descriptors.txt"
    /etc/glacier2/enforce --check
}

burn_cds() {
    local n package iso sectors
    mkdir -m 700 "$STATE/discs"

    for n in {1..7}; do
        package=$STATE/discs/signer_$n
        iso=$STATE/discs/signer_$n.iso
        mkdir -m 700 "$package"

        rpc -rpcwallet="signer_$n" backupwallet "$package/wallet.dat"
        cp "$STATE/descriptors.txt" "$ROOT/RECOVERY.md" "$package/"
        printf 'Glacier-2 signer %s of 7\nNetwork: %s\nUNENCRYPTED PRIVATE BACKUP\n' "$n" "$CHAIN" >"$package/DISC.txt"
        (cd "$package" && sha256sum wallet.dat descriptors.txt RECOVERY.md DISC.txt >SHA256SUMS)

        xorriso -as mkisofs -quiet -R -J -V "GLACIER2_S$n" -o "$iso" "$package"
        confirm "Insert a new blank CD-R in $DRIVE for signer $n." "BURN SIGNER $n"
        findmnt -rn -S "$DRIVE" >/dev/null && die 'Disc is mounted; unmount it first.'
        xorriso -outdev "$DRIVE" -toc >"$STATE/discs/media_$n.log" 2>&1
        grep -Eq 'Media current:.*CD-R[[:space:]]*$' "$STATE/discs/media_$n.log" || die 'Expected a CD-R.'
        grep -Eq 'Media status : is blank' "$STATE/discs/media_$n.log" || die 'Disc is not blank.'
        xorriso -as cdrecord -v dev="$DRIVE" -dao "$iso"
        sync
        eject "$DRIVE"

        printf 'Reinsert signer %s disc, unmount it if necessary, then press Enter: ' "$n" >/dev/tty
        read -r </dev/tty
        findmnt -rn -S "$DRIVE" >/dev/null && die 'Disc is mounted; unmount it first.'
        sectors=$(( $(stat -c %s "$iso") / 2048 ))
        cmp -- "$iso" <(dd if="$DRIVE" bs=2048 count="$sectors" iflag=fullblock status=none)
        eject "$DRIVE"

        confirm "Label and store Signer $n of 7 ($CHAIN) separately." "STORED SIGNER $n"
    done
}

main() {
    SKIP_CD=0
    case ${1:-} in
        '') ;;
        --test) SKIP_CD=1 ;;
        -h|--help)
            printf 'Usage: sudo ./setup.sh [--test]\n--test performs real airgapping and wallet creation but does not burn CDs.\n'
            return ;;
        *) die 'Unknown option.' ;;
    esac
    [[ $# -le 1 ]] || die 'Too many arguments.'

    [[ $EUID == 0 ]] || die 'Run with sudo on a clean Ubuntu installation.'
    [[ -z ${SSH_CONNECTION:-}${SSH_TTY:-} ]] || die 'Do not run over SSH.'
    [[ -d /run/systemd/system ]] || die 'A booted systemd system is required.'
    source /etc/os-release
    [[ $ID == ubuntu && ( $VERSION_ID == 24.04 || $VERSION_ID == 26.04 ) ]] || die 'Ubuntu 24.04 or 26.04 is required.'

    for path in "$STATE" /etc/glacier2 /opt/glacier2 /etc/systemd/system/glacier2-airgap.service; do
        [[ ! -e $path && ! -L $path ]] || die "Existing Glacier state: $path"
    done

    exec 9>/run/lock/glacier2.lock
    flock -n 9 || die 'Another Glacier-2 setup is running.'

    CHAIN=${GLACIER_CHAIN:-main}
    [[ $CHAIN == main || $CHAIN == regtest || $CHAIN == signet ]] || die 'Invalid GLACIER_CHAIN.'
    DRIVE=${GLACIER_DRIVE:-/dev/sr0}
    (( SKIP_CD )) || [[ -t 0 && -t 1 && $DRIVE =~ ^/dev/sr[0-9]+$ && -b $DRIVE ]] || die 'A local terminal and optical drive are required.'

    mkdir -m 700 "$STATE"
    trap cleanup EXIT
    trap 'log "Failure at line $LINENO."' ERR

    install_core
    airgap
    make_wallet
    (( SKIP_CD )) || burn_cds

    if (( SKIP_CD )); then
        log 'Wallet created. CDs were skipped; do not fund this test setup.'
    else
        log 'Done. Seven CDs were burned and read back successfully. Keep the machine offline.'
    fi
}

[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
