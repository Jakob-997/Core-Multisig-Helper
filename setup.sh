#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
export LC_ALL=C PATH=/usr/sbin:/usr/bin:/sbin:/bin

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
STATE=/var/lib/glacier2
CORE=/opt/glacier2/core
CORE_VERSION=32.0rc2
CORE_STARTED=0

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
need() { command -v "$1" >/dev/null || die "Missing command: $1"; }
rpc() { "$CORE/bin/bitcoin-cli" -datadir="$DATA" -chain="$CHAIN" -rpcport=18459 "$@"; }

stop_core() {
    (( CORE_STARTED )) || return 0
    rpc stop >/dev/null 2>&1 || true
    [[ -z ${CORE_PID:-} ]] || wait "$CORE_PID" || true
    CORE_STARTED=0
}

cleanup() {
    local status=$?
    trap - EXIT
    stop_core
    (( status == 0 )) || log 'Stopped after failure. Airgap restrictions remain; preserve all state and never regenerate over it.'
    exit "$status"
}

start_core() {
    [[ ! -e $DATA/bitcoin.conf ]] || die 'Unexpected bitcoin.conf in dedicated data directory.'
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
            rpc help addhdkey >/dev/null
            rpc help derivehdkey >/dev/null
            return
        fi
        kill -0 "$CORE_PID" 2>/dev/null || die 'Core exited during startup.'
        sleep 1
    done
    die 'Core startup timed out.'
}

confirm() {
    local answer
    printf '%s\nType %s: ' "$1" "$2" >/dev/tty
    read -r answer </dev/tty
    [[ $answer == "$2" ]] || die 'Confirmation did not match.'
}

desktop_user() {
    runuser -u "$DESKTOP_USER" -- env HOME="$DESKTOP_HOME" \
        XDG_RUNTIME_DIR="/run/user/$DESKTOP_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$DESKTOP_UID/bus" "$@"
}

desktop_preflight() {
    DESKTOP_USER=${SUDO_USER:-}
    [[ -n $DESKTOP_USER && $DESKTOP_USER != root ]] || die 'Run sudo from your logged-in Ubuntu GNOME desktop user.'
    DESKTOP_UID=$(id -u "$DESKTOP_USER")
    DESKTOP_GID=$(id -g "$DESKTOP_USER")
    DESKTOP_HOME=$(getent passwd "$DESKTOP_USER" | cut -d: -f6)
    [[ -d $DESKTOP_HOME && -S /run/user/$DESKTOP_UID/bus ]] || die 'No active desktop session found for the sudo user.'
    desktop_user gsettings list-schemas | grep -Fx org.gnome.desktop.background >/dev/null || die 'GNOME background settings are required.'
    desktop_user gsettings writable org.gnome.desktop.background picture-uri | grep -Fx true >/dev/null || die 'Desktop background is locked by policy.'
    [[ ! -e $DESKTOP_HOME/.local/share/glacier2 && ! -L $DESKTOP_HOME/.local/share/glacier2 ]] || die 'Existing desktop wallet/identity state; refusing overwrite.'
    [[ ! -e $DESKTOP_HOME/.local/share/applications/glacier2-bitcoin.desktop ]] || die 'Existing Glacier desktop launcher.'
}

assert_airgap() {
    /etc/glacier2/enforce --check
    [[ $(cat /proc/sys/kernel/modules_disabled) == 1 ]] || die 'Kernel module loading is not locked.'
}

install_core() {
    local arch archive
    case $(uname -m) in
        x86_64) arch=x86_64-linux-gnu ;;
        aarch64) arch=aarch64-linux-gnu ;;
        *) die 'Unsupported CPU.' ;;
    esac
    archive="$ROOT/vendor/bitcoin-$CORE_VERSION-$arch.tar.gz"
    [[ -f $archive ]] || die "Bundled Bitcoin Core archive missing: $archive"

    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
    apt-get update
    apt-get install -y --no-install-recommends \
        ca-certificates jq python3 python3-pil fonts-dejavu-core \
        nftables rfkill iproute2 xorriso eject kmod initramfs-tools util-linux \
        libglib2.0-bin xdg-user-dirs desktop-file-utils xwayland libfontconfig1 \
        libx11-xcb1 libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
        libxcb-render-util0 libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0 libegl1 libgl1

    desktop_preflight
    for cmd in jq python3 nft rfkill ip xorriso eject modprobe update-initramfs update-grub; do need "$cmd"; done
    [[ -d /etc/default/grub.d ]] || die 'A GRUB installation is required for persistent boot hardening.'

    mkdir -p /opt/glacier2 "$STATE/extracted"
    tar -xzf "$archive" --no-same-owner -C "$STATE/extracted"
    [[ -d $STATE/extracted/bitcoin-$CORE_VERSION/bin ]] || die 'Unexpected bundled Core archive layout.'
    mv "$STATE/extracted/bitcoin-$CORE_VERSION" "$CORE"
    "$CORE/bin/bitcoind" --version | head -n 1 >"$STATE/core-version"
    grep -q 'v32.0.0rc2' "$STATE/core-version" || die 'Unexpected Core version.'

    (( SKIP_CD )) || xorriso -devices >"$STATE/optical-devices.txt" 2>&1
    if (( ! SKIP_CD )); then modprobe sr_mod; modprobe sg; fi
    modprobe rfkill
    modprobe nf_tables
    start_core
    stop_core
}
airgap() {
    local path module driver device
    log 'Applying persistent airgap rules. Physically disconnect Ethernet and remove/disable radio hardware; software cannot defeat malicious root, kernel or firmware.'
    swapoff -a
    [[ $(awk 'END {print NR}' /proc/swaps) == 1 ]] || die 'Swap is still active.'
    ulimit -c 0

    install -d -m 700 /etc/glacier2
    install -m 700 "$ROOT/lib/enforce-airgap.sh" /etc/glacier2/enforce
    install -m 600 "$ROOT/config/airgap.nft" /etc/glacier2/airgap.nft
    printf '%s\n' "$SKIP_CD" >/etc/glacier2/skip-cd
    nft list table inet glacier2 >/dev/null 2>&1 && die 'Firewall table already exists.'
    nft -f /etc/glacier2/airgap.nft
    rfkill block all

    for module in NetworkManager NetworkManager-wait-online systemd-networkd systemd-networkd-wait-online systemd-networkd.socket systemd-resolved wpa_supplicant bluetooth ModemManager avahi-daemon avahi-daemon.socket networking connman iwd; do
        systemctl mask --now "$module" >/dev/null
    done

    : >"$STATE/blocked-modules"
    while IFS= read -r path; do
        module=$(basename "$path")
        module=${module%%.ko*}
        [[ $module =~ ^[a-zA-Z0-9_-]+$ ]] || die 'Unexpected module filename.'
        printf '%s\n' "$module" >>"$STATE/blocked-modules"
    done < <(find /lib/modules -type f \( \
        -path '*/kernel/drivers/net/*' -o -path '*/kernel/drivers/bluetooth/*' \
        -o -path '*/kernel/drivers/nfc/*' -o -path '*/kernel/drivers/uwb/*' \
        -o -path '*/kernel/drivers/media/radio/*' -o -path '*/kernel/drivers/media/usb/airspy/*' \
        -o -path '*/kernel/drivers/media/usb/hackrf/*' -o -path '*/kernel/drivers/media/usb/msi2500/*' \
        \) -name '*.ko*')

    printf '%s\n' bluetooth btusb cfg80211 mac80211 >"$STATE/boot-blocked-modules"
    for path in /sys/class/net/*; do
        [[ ${path##*/} == lo ]] && continue
        if [[ -L $path/device/driver/module ]]; then
            module=$(basename "$(readlink -f "$path/device/driver/module")")
            printf '%s\n' "$module" >>"$STATE/blocked-modules"
            printf '%s\n' "$module" >>"$STATE/boot-blocked-modules"
        fi
    done
    printf '%s\n' bluetooth btusb btrtl btintel btbcm bnep rfcomm cfg80211 mac80211 nfc ieee802154 mac802154 ieee802154_6lowpan >>"$STATE/blocked-modules"
    sort -u "$STATE/blocked-modules" -o "$STATE/blocked-modules"
    while read -r module; do printf 'blacklist %s\ninstall %s /bin/false\n' "$module" "$module"; done <"$STATE/blocked-modules" >/etc/modprobe.d/glacier2.conf

    for path in /sys/class/net/*; do
        [[ ${path##*/} == lo ]] && continue
        ip address flush dev "${path##*/}"
        ip -6 address flush dev "${path##*/}"
        ip link set dev "${path##*/}" down
        if [[ -L $path/device/driver && -e $path/device/driver/unbind ]]; then
            driver=$(readlink -f "$path/device/driver")
            device=$(basename "$(readlink -f "$path/device")")
            printf '%s' "$device" >"$driver/unbind"
        fi
    done
    while read -r module; do modprobe -r "$module" 2>/dev/null || true; done <"$STATE/blocked-modules"

    # shellcheck disable=SC2016
    printf 'GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX rfkill.default_state=0 module_blacklist=%s"\n' "$(sort -u "$STATE/boot-blocked-modules" | paste -sd,)" >/etc/default/grub.d/99-glacier2.cfg
    cat >/etc/udev/rules.d/99-glacier2.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="net", KERNEL!="lo", RUN+="/usr/sbin/ip link set dev %k down"
ACTION=="add", SUBSYSTEM=="rfkill", RUN+="/usr/sbin/rfkill block all"
EOF
    install -m 644 "$ROOT/config/glacier2-airgap.service" /etc/systemd/system/glacier2-airgap.service
    systemctl daemon-reload
    systemctl enable glacier2-airgap.service
    systemctl is-enabled --quiet glacier2-airgap.service || die 'Airgap boot service was not enabled.'
    udevadm control --reload-rules
    update-initramfs -u -k all
    update-grub
    /etc/glacier2/enforce
    assert_airgap
}

wallets() {
    assert_airgap
    start_core
    python3 "$ROOT/lib/wallets.py" "$CORE/bin/bitcoin-cli" "$DATA" "$CHAIN" "$STATE/public"
    assert_airgap
}

desktop_identity() {
    local desktop_mode=watch-only desktop_data desktop_chain_dir desktop_wallet_dir n
    assert_airgap
    desktop_preflight
    install -d -m 755 /opt/glacier2 /opt/glacier2/identity
    install -m 644 "$ROOT/assets/bitcoin-core.svg" /opt/glacier2/identity/bitcoin-core.svg
    install -m 644 "$ROOT/assets/BITCOIN-COPYING" /opt/glacier2/identity/BITCOIN-COPYING
    python3 "$ROOT/lib/desktop_identity.py" generate /opt/glacier2/identity "$CHAIN"

    rpc -rpcwallet=watch_only getwalletinfo | jq -e '.private_keys_enabled == false' >/dev/null
    rpc -rpcwallet=watch_only backupwallet "$STATE/watch-only-desktop.dat"
    install -m 644 "$STATE/watch-only-desktop.dat" /opt/glacier2/identity/watch-only.dat
    install -m 644 "$ROOT/lib/desktop_identity.py" /opt/glacier2/identity/setup.py

    (( SKIP_CD )) && desktop_mode=test-signers
    desktop_user python3 /opt/glacier2/identity/setup.py apply /opt/glacier2/identity "$CHAIN" "$desktop_mode"

    if (( SKIP_CD )); then
        desktop_data="$DESKTOP_HOME/.local/share/glacier2/core"
        desktop_chain_dir="$desktop_data"
        [[ $CHAIN == main ]] || desktop_chain_dir="$desktop_data/$CHAIN"
        desktop_wallet_dir="$desktop_chain_dir/wallets"
        for n in {1..7}; do
            rpc -rpcwallet="signer_$n" getwalletinfo | jq -e '.private_keys_enabled == true' >/dev/null
            install -d -m 700 -o "$DESKTOP_UID" -g "$DESKTOP_GID" "$desktop_wallet_dir/signer_$n"
            rpc -rpcwallet="signer_$n" backupwallet "$desktop_wallet_dir/signer_$n/wallet.dat"
            chown "$DESKTOP_UID:$DESKTOP_GID" "$desktop_wallet_dir/signer_$n/wallet.dat"
            chmod 600 "$desktop_wallet_dir/signer_$n/wallet.dat"
        done
        log 'TEST FLAG: all seven signer wallets are available to desktop Bitcoin-Qt for inspection. Do not fund this test setup.'
    fi

    cp /opt/glacier2/identity/identity.json "$STATE/public/identity.json"
    log "Recognition code: $(jq -r .code /opt/glacier2/identity/identity.json)"
    log "Background color: $(jq -r .color /opt/glacier2/identity/identity.json)"
    log 'Record the code/color on separate paper. Visual cues do not prove integrity or prevent exfiltration.'
}

backup_cd() {
    local n package iso readback sectors
    [[ ! -e $STATE/discs ]] || die 'Disc staging already exists; refusing overwrite.'
    mkdir -m 700 "$STATE/discs"

    for n in {1..7}; do
        assert_airgap
        package=$STATE/discs/signer_$n
        iso=$STATE/discs/signer_$n.iso
        readback=$STATE/discs/readback_$n.iso
        mkdir -m 700 "$package"
        rpc -rpcwallet="signer_$n" backupwallet "$package/wallet.dat"
        [[ -s $package/wallet.dat ]] || die 'Empty backup.'
        cp "$STATE/public/manifest.json" "$STATE/public/descriptors.txt" "$STATE/public/identity.json" "$package/"
        cp "$ROOT/RECOVERY.md" "$package/RECOVERY.md"
        printf 'GLACIER-2 PROTOTYPE\nSigner: %s of 7\nNetwork: %s\nUNENCRYPTED PRIVATE BACKUP. Keep physically separate.\n' "$n" "$CHAIN" >"$package/DISC.txt"
        (cd "$package" && sha256sum wallet.dat manifest.json descriptors.txt identity.json RECOVERY.md DISC.txt >SHA256SUMS)
        [[ $(find "$package" -maxdepth 1 -type f | wc -l) == 7 ]] || die 'Unexpected files in disc package.'

        xorriso -as mkisofs -quiet -R -J -V "GLACIER2_S$n" -o "$iso" "$package"
        [[ $(stat -c %s "$iso") -lt 650000000 ]] || die 'Image too large for supported CD.'
        confirm "Insert a NEW BLANK CD-R in $DRIVE for signer $n. No rewritable media and no existing sessions." "BURN SIGNER $n"
        findmnt -rn -S "$DRIVE" >/dev/null && die 'Optical disc is mounted; unmount it before retrying.'
        xorriso -outdev "$DRIVE" -toc >"$STATE/discs/media_$n.log" 2>&1
        grep -Eq 'Media current:.*CD-R[[:space:]]*$' "$STATE/discs/media_$n.log" || die 'Expected CD-R media (not CD-RW/DVD).'
        grep -Eq 'Media status : is blank' "$STATE/discs/media_$n.log" || die 'Disc is not blank.'
        xorriso -as cdrecord -v dev="$DRIVE" -dao "$iso"
        sync
        eject "$DRIVE"

        printf 'Remove and reinsert signer %s disc. Unmount it if the desktop mounts it, then press Enter: ' "$n" >/dev/tty
        read -r </dev/tty
        findmnt -rn -S "$DRIVE" >/dev/null && die 'Readback disc is mounted; unmount it first.'
        sectors=$(( $(stat -c %s "$iso") / 2048 ))
        dd if="$DRIVE" of="$readback" bs=2048 count="$sectors" iflag=fullblock status=none
        cmp -- "$iso" "$readback"
        mkdir -m 700 "$STATE/discs/readback_$n"
        xorriso -osirrox on -indev "$readback" -extract / "$STATE/discs/readback_$n" >/dev/null 2>&1
        (cd "$STATE/discs/readback_$n" && sha256sum --check --strict SHA256SUMS)
        cmp "$package/wallet.dat" "$STATE/discs/readback_$n/wallet.dat"
        printf '%s signer_%s VERIFIED\n' "$(date -u +%FT%TZ)" "$n" >>"$STATE/discs/verified.log"
        eject "$DRIVE"
        confirm "Label this disc Signer $n of 7 ($CHAIN), store it separately, and keep it offline." "STORED SIGNER $n"
    done
    [[ $(wc -l <"$STATE/discs/verified.log") == 7 ]] || die 'Expected seven verified discs.'
}

stage() {
    log "Starting: $1"
    "$1"
    printf '%s\n' "$(date -u +%FT%TZ)" >"$STATE/$1.complete"
    log "Completed: $1"
}

main() {
    SKIP_CD=0
    for option in "$@"; do
        case $option in
            --test) SKIP_CD=1 ;;
            --help|-h)
                printf 'Usage: sudo bash setup.sh [--test]\n--test: real hardening and wallet creation, but skip CDs and expose test signer copies in Bitcoin-Qt. NOT a dry run.\n'
                return ;;
            *) die "Unknown option: $option (use --help)" ;;
        esac
    done

    [[ $EUID == 0 ]] || die 'Run with sudo bash setup.sh on a disposable Ubuntu installation.'
    (( SKIP_CD )) || [[ -t 0 && -t 1 ]] || die 'A local terminal is required for swapping CDs. Use --test to skip CDs.'
    [[ -z ${SSH_CONNECTION:-}${SSH_TTY:-} ]] || die 'Do not run over SSH.'
    [[ -d /run/systemd/system ]] || die 'A booted systemd host is required.'

    # shellcheck source=/dev/null
    source /etc/os-release
    [[ $ID == ubuntu && ( $VERSION_ID == 24.04 || $VERSION_ID == 26.04 ) ]] || die 'Prototype supports Ubuntu 24.04/26.04 only.'

    for path in "$STATE" /etc/glacier2 /opt/glacier2 /etc/modprobe.d/glacier2.conf \
        /etc/default/grub.d/99-glacier2.cfg /etc/udev/rules.d/99-glacier2.rules \
        /etc/systemd/system/glacier2-airgap.service; do
        [[ ! -e $path && ! -L $path ]] || die "Existing Glacier state/configuration: $path"
    done

    need flock
    exec 9>/run/lock/glacier2.lock
    flock -n 9 || die 'Another Glacier runner is active.'

    CHAIN=${GLACIER_CHAIN:-main}
    [[ $CHAIN == main || $CHAIN == regtest || $CHAIN == signet ]] || die 'GLACIER_CHAIN must be main, regtest or signet.'
    DRIVE=${GLACIER_DRIVE:-/dev/sr0}
    (( SKIP_CD )) || [[ $DRIVE =~ ^/dev/sr[0-9]+$ && -b $DRIVE ]] || die 'Set GLACIER_DRIVE to an optical block device, for example /dev/sr0.'
    DATA=$STATE/core-data

    log "Creating seven unencrypted $CHAIN signers behind a persistent software airgap. Prototype: do not use meaningful funds before recovery/spend tests."
    (( ! SKIP_CD )) || log 'TEST FLAG: real hardening and wallet creation; CD backups skipped. Not a dry run.'

    mkdir -m 700 "$STATE"
    trap cleanup EXIT
    trap 'log "Failure at line $LINENO (command suppressed to avoid secret disclosure)."' ERR
    printf '%s\n' "$CHAIN" >"$STATE/chain"
    printf '%s\n' "$ROOT" >"$STATE/source-location"
    printf '%s\n' "$SKIP_CD" >"$STATE/skip-cd"

    stage install_core
    stage airgap
    stage wallets
    stage desktop_identity
    (( SKIP_CD )) || stage backup_cd

    if (( SKIP_CD )); then
        log 'Setup finished; CDs deliberately skipped. No recovery media exists. Keep offline; do not fund this test setup.'
    else
        log 'Seven discs verified. Keep the machine offline. Follow RECOVERY.md before trusting this wallet.'
    fi
}

[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
