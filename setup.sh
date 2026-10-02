#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077

cd "$(dirname "${BASH_SOURCE[0]}")"
STATE=/dev/shm/core-multisig-helper
CORE=$STATE/core
DATA=$STATE/data
DRIVE=/dev/sr0

die(){ echo "ERROR: $*" >&2; exit 1; }
(( EUID == 0 )) || die 'Run Core Multisig Helper with sudo: sudo bash ./setup.sh'
rpc(){ "$CORE/bin/bitcoin-cli" -datadir="$DATA" -rpcport=18459 "$@"; }
node(){ local m=$1; shift; printf '%s\n' "$@" | rpc -stdin "$m"; }
wallet(){ local w=$1 m=$2; shift 2; printf '%s\n' "$@" | rpc -rpcwallet="$w" -stdin "$m"; }

airgap(){
    nft -f - <<'EOF'
flush ruleset
table inet cmh {
 chain input { type filter hook input priority -300; policy drop; iifname "lo" accept; }
 chain output { type filter hook output priority -300; policy drop; oifname "lo" accept; }
}
EOF
    systemctl stop NetworkManager.service wpa_supplicant.service ModemManager.service systemd-networkd.service 2>/dev/null || true
    rfkill block all 2>/dev/null || true
    for i in /sys/class/net/*; do n=${i##*/}; [ "$n" = lo ] || ip link set "$n" down 2>/dev/null || true; done
    [[ $MODE == generate ]] && echo 'AIRGAP ACTIVE — networking disabled before key generation.' || echo 'AIRGAP ACTIVE — networking disabled before signer wallet loading.'
}

install_core(){
    mkdir "$CORE" "$DATA"
    tar -xzf bitcoin-core.tar.gz --strip-components=1 -C "$CORE"
    [[ $MODE == spend ]] && return
    "$CORE/bin/bitcoind" -datadir="$DATA" -daemonwait -networkactive=0 -listen=0 -rpcport=18459
    trap 'rpc stop >/dev/null 2>&1 || true' EXIT
}

spend_wallet(){
    local src dir desc commas gui_user launcher
    read -rp 'Ensure ONE signer backup disc is inserted and mounted, then press Enter: ' </dev/tty
    dir=$(findmnt -nr -S "$DRIVE" -o TARGET 2>/dev/null || true)
    [[ -n $dir ]] || die "Signer disc in $DRIVE is not mounted."
    src=$dir/wallet.dat
    [[ -f $src ]] || die 'Signer backup is missing wallet.dat.'
    [[ -f $dir/descriptors.txt ]] || die 'Signer backup is missing descriptors.txt.'
    desc=$(<"$dir/descriptors.txt")
    [[ $desc =~ sortedmulti\(([0-9]+), ]] || die 'Could not read multisig policy.'
    M=${BASH_REMATCH[1]}; commas=${desc//[^,]/}; N=${#commas}
    [[ $M -le $N && $N -ge 2 ]] || die 'Invalid multisig policy.'
    mkdir -p "$DATA/wallets/signer"
    cp "$src" "$DATA/wallets/signer/wallet.dat"
    gui_user=${SUDO_USER:-}; [[ -n $gui_user && $gui_user != root ]] || die 'Run Core Multisig Helper with sudo from the Ubuntu desktop user.'
    chown -R "$gui_user:$(id -gn "$gui_user")" "$STATE"
    launcher="/home/$gui_user/Desktop/Bitcoin Core Signer.desktop"; printf '[Desktop Entry]\nType=Application\nName=Bitcoin Core Signer\nExec=%s/bin/bitcoin-qt -datadir=%s -walletdir=%s/wallets -networkactive=0 -listen=0 -wallet=signer\nIcon=%s/share/pixmaps/bitcoin256.png\nTerminal=false\n' "$CORE" "$DATA" "$DATA" "$CORE" >"$launcher"; chown "$gui_user:$(id -gn "$gui_user")" "$launcher"; chmod 755 "$launcher"; sudo -H -u "$gui_user" env XDG_RUNTIME_DIR="/run/user/$(id -u "$gui_user")" gio set "$launcher" metadata::trusted true 2>/dev/null || true
    echo "Wallet policy detected: $M-of-$N multisig. You need $M different signer backups out of $N total."
    echo 'Bitcoin Core will open with this signer wallet. Use it to verify receive addresses or sign a PSBT.'
    echo "If signing, save the partially signed PSBT to your transfer USB, then power off and repeat with a different signer until $M signers have signed."
    echo "After $M different signers have signed, take the completed transaction online and broadcast it from your node."
    sudo -H -u "$gui_user" env XDG_RUNTIME_DIR="/run/user/$(id -u "$gui_user")" "$CORE/bin/bitcoin-qt" -datadir="$DATA" -walletdir="$DATA/wallets" -networkactive=0 -listen=0 -wallet=signer
    echo 'Bitcoin Core closed. Power off before using another signer.'
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
    request=$(jq -cn --arg desc "$raw#$checksum" '[{desc:$desc,active:true,timestamp:0,range:[0,999]}]')
    wallet watch_only importdescriptors "$request" | jq -e '.[0].success == true' >/dev/null || die 'Failed to import WATCH ONLY descriptor.'
    [[ $(rpc -rpcwallet=watch_only getwalletinfo | jq -r .private_keys_enabled) == false ]] || die 'WATCH ONLY contains private keys.'

    for ((i=1;i<=N;i++)); do
        private="${raw/${xpub[i]}/${xprv[i]}}"
        checksum=$(node getdescriptorinfo "$private" | jq -r .checksum)
        request=$(jq -cn --arg desc "$private#$checksum" '[{desc:$desc,active:true,timestamp:0,range:[0,999]}]')
        wallet "signer_$i" importdescriptors "$request" | jq -e '.[0].success == true' >/dev/null || die "Failed to import signer $i descriptor."
    done
}

burn_cds(){
    local i iso sectors
    mkdir "$STATE/cd"
    cp "$STATE/descriptors.txt" "$STATE/cd/"
    rpc -rpcwallet=watch_only backupwallet "$STATE/cd/watch_only.dat"
    iso=$STATE/watch_only.iso
    xorriso -as mkisofs -quiet -r -J -o "$iso" "$STATE/cd"
    read -rp "Insert pre-labeled blank CD-R for WATCH ONLY, then press Enter: " </dev/tty
    xorriso -as cdrecord -v dev="$DRIVE" -dao "$iso"
    eject "$DRIVE"
    read -rp "Reinsert WATCH ONLY, then press Enter: " </dev/tty
    sectors=$(( $(stat -c %s "$iso") / 2048 ))
    cmp "$iso" <(dd if="$DRIVE" bs=2048 count="$sectors" status=none) || die 'WATCH ONLY disc verification failed.'
    eject "$DRIVE"
    echo "WATCH ONLY verified. Use this disc on the online computer."
    rm "$STATE/cd/watch_only.dat"
    for ((i=1;i<=N;i++)); do
        rm -f "$STATE/cd/wallet.dat"
        rpc -rpcwallet="signer_$i" backupwallet "$STATE/cd/wallet.dat"
        iso=$STATE/signer_$i.iso
        xorriso -as mkisofs -quiet -r -J -o "$iso" "$STATE/cd"
        read -rp "Insert pre-labeled blank CD-R for signer $i, then press Enter: " </dev/tty
        xorriso -as cdrecord -v dev="$DRIVE" -dao "$iso"
        eject "$DRIVE"
        read -rp "Reinsert signer $i, then press Enter: " </dev/tty
        sectors=$(( $(stat -c %s "$iso") / 2048 ))
        cmp "$iso" <(dd if="$DRIVE" bs=2048 count="$sectors" status=none) || die "Signer $i disc verification failed."
        eject "$DRIVE"
        echo "Signer $i verified. Store it separately."
    done
}

echo 'CORE MULTISIG HELPER'
read -rp 'Select mode: generate or spend: ' MODE </dev/tty
[[ $MODE == generate || $MODE == spend ]] || die 'Enter exactly: generate or spend.'
[[ ! -e $STATE ]] || { [[ $MODE == generate ]] || die 'Existing Core Multisig Helper state. If you just generated a wallet, reboot into a fresh Ubuntu Live session before spending; spend mode is intentionally fresh-session only.'; rpc getblockchaininfo >/dev/null 2>&1 && die 'A Core Multisig Helper wallet is still running. Finish it or reboot before generating another.'; read -rp 'WARNING: A previous Core Multisig Helper wallet was detected. Type NEW to permanently delete it and create a completely new wallet. Old CDs/backups belong to the old wallet and MUST NOT be mixed with the new one: ' RESET </dev/tty; [[ $RESET == NEW ]] || die 'Canceled.'; rm -rf -- "$STATE"; }
[[ $(uname -m) == x86_64 ]] || die 'Requires an x86-64 (amd64) computer.'
for c in nft rfkill ip systemctl swapoff sha256sum findmnt; do command -v "$c" >/dev/null || die "Missing $c."; done

if [[ $MODE == generate ]]; then
    read -rp 'Enter multisig policy in m-n format (for example 2-4): ' MN </dev/tty
    MN=${MN//-of-/-}; MN=${MN// of /-}; M=${MN%-*}; N=${MN#*-}
    [[ $M =~ ^[1-9][0-9]*$ && $N =~ ^[1-9][0-9]*$ && $M -le $N && $N -ge 2 && $N -le 20 ]] || die 'Enter m-n, for example 2-5.'
    [[ -b $DRIVE ]] || die "No optical drive: $DRIVE"
    for c in xorriso eject jq; do command -v "$c" >/dev/null || die "Missing $c."; done
fi

echo '0255103718033e6aee15fa944717fc277e047b845bff1e7408af0ea732d8d0c1  bitcoin-core.tar.gz' | sha256sum -c - >/dev/null || die 'Bad Bitcoin Core checksum.'
[[ $(findmnt -n -o FSTYPE /dev/shm) == tmpfs ]] || die '/dev/shm is not RAM-backed tmpfs.'
swapoff -a
airgap
mkdir -m 700 "$STATE"
install_core
[[ $MODE == spend ]] && { spend_wallet; exit; }
make_wallet
burn_cds
rpc stop
trap - EXIT
echo 'Done. All backups verified. Power off the computer.'
