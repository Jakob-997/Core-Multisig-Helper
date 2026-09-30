#!/usr/bin/env bash
install_core() {
    local arch archive base expected name fpr actual
    case $(uname -m) in x86_64) arch=x86_64-linux-gnu;; aarch64) arch=aarch64-linux-gnu;; *) die 'Unsupported CPU.';; esac
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl gnupg jq python3 nftables rfkill iproute2 xorriso eject kmod initramfs-tools util-linux
    apt-get install -y --no-install-recommends python3-pil fonts-dejavu-core libglib2.0-bin xdg-user-dirs desktop-file-utils xwayland libfontconfig1 libx11-xcb1 libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0 libegl1 libgl1
    # Check the actual sudo user's desktop session before networking is disabled.
    # shellcheck source=modules/desktop_identity.sh
    source "$ROOT/modules/desktop_identity.sh"
    desktop_preflight
    for name in curl gpg jq python3 nft rfkill ip xorriso eject modprobe update-initramfs; do need "$name"; done
    need update-grub
    [[ -d /etc/default/grub.d ]] || die 'A GRUB installation is required for persistent boot hardening.'
    mkdir -m 700 "$STATE/downloads" "$STATE/gnupg"
    base=https://bitcoincore.org/bin/bitcoin-core-32.0/test.rc2
    archive=bitcoin-32.0rc2-$arch.tar.gz
    for name in SHA256SUMS SHA256SUMS.asc "$archive"; do
        curl --proto '=https' --tlsv1.2 --fail --show-error --location --retry 3 "$base/$name" -o "$STATE/downloads/$name"
    done
    # Pin primary fingerprints, not short IDs or an arbitrary downloaded keyring.
    for name in hebasto achow101; do
        case $name in
            hebasto) fpr=D1DBF2C4B96F2DEBF4C16654410108112E7EA81F;;
            achow101) fpr=152812300785C96444D3334D17565732E08E5E41;;
        esac
        curl --proto '=https' --tlsv1.2 --fail --show-error --location --retry 3 \
            "https://raw.githubusercontent.com/bitcoin-core/guix.sigs/main/builder-keys/$name.gpg" -o "$STATE/downloads/$name.gpg"
        actual=$(gpg --homedir "$STATE/gnupg" --batch --with-colons --show-keys "$STATE/downloads/$name.gpg" | awk -F: '$1=="fpr" {print $10; exit}')
        [[ $actual == "$fpr" ]] || die "Fingerprint mismatch for $name."
        gpg --homedir "$STATE/gnupg" --batch --import "$STATE/downloads/$name.gpg"
    done
    # Missing signatures from other builders can make GPG nonzero. Require both
    # pinned primary fingerprints in VALIDSIG and reject bad/expired/revoked signatures.
    gpg --homedir "$STATE/gnupg" --batch --status-fd 1 --verify \
        "$STATE/downloads/SHA256SUMS.asc" "$STATE/downloads/SHA256SUMS" \
        >"$STATE/downloads/signature-status" 2>"$STATE/downloads/signature-log" || true
    python3 "$ROOT/lib/verify_signatures.py" "$STATE/downloads/signature-status"
    expected=$(awk -v f="$archive" '$2==f {print $1}' "$STATE/downloads/SHA256SUMS")
    [[ $expected =~ ^[a-f0-9]{64}$ ]] || die 'Missing, duplicate or malformed archive checksum.'
    printf '%s  %s\n' "$expected" "$STATE/downloads/$archive" | sha256sum --check --strict
    mkdir -p /opt/glacier2 "$STATE/extracted"
    tar -xzf "$STATE/downloads/$archive" --no-same-owner -C "$STATE/extracted"
    [[ -d $STATE/extracted/bitcoin-32.0rc2/bin ]] || die 'Unexpected archive layout.'
    mv "$STATE/extracted/bitcoin-32.0rc2" "$CORE"
    "$CORE/bin/bitcoind" --version | head -n 1 >"$STATE/core-version"
    grep -q 'v32.0.0rc2' "$STATE/core-version" || die 'Unexpected Core version.'
    xorriso -devices >"$STATE/optical-devices.txt" 2>&1
    # Load optical and firewall dependencies before the irreversible runtime lock.
    modprobe sr_mod
    modprobe sg
    modprobe rfkill
    modprobe nf_tables
    start_core
    stop_core
    # Consumed by common.sh cleanup/start_core in the sourcing shell.
    # shellcheck disable=SC2034
    CORE_STARTED=0
}
