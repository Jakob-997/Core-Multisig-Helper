#!/usr/bin/env bash
set -Eeuo pipefail
set +x
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
[[ $EUID == 0 ]] || die 'Run with sudo bash setup.sh on a disposable Ubuntu installation.'
[[ $# == 0 ]] || die 'No arguments supported. See README for configuration.'
[[ -t 0 && -t 1 ]] || die 'A local interactive terminal is required.'
[[ -z ${SSH_CONNECTION:-}${SSH_TTY:-} ]] || die 'Do not run over SSH.'
[[ -d /run/systemd/system ]] || die 'A booted systemd host is required.'
# shellcheck source=/dev/null
source /etc/os-release
[[ $ID == ubuntu && ( $VERSION_ID == 24.04 || $VERSION_ID == 26.04 ) ]] || die 'Prototype supports Ubuntu 24.04/26.04 only.'
[[ ! -e /var/lib/glacier2 ]] || die 'Existing /var/lib/glacier2: refusing to replace or regenerate keys. See recovery guide.'
[[ ! -e /etc/glacier2 && ! -e /opt/glacier2 ]] || die 'Existing Glacier installation detected; inspect it first.'
for path in /var/lib/glacier2 /etc/glacier2 /opt/glacier2 /etc/modprobe.d/glacier2.conf /etc/default/grub.d/99-glacier2.cfg /etc/udev/rules.d/99-glacier2.rules /etc/systemd/system/glacier2-airgap.service; do
    [[ ! -e $path && ! -L $path ]] || die "Existing state/configuration: $path"
done
need flock
exec 9>/run/lock/glacier2.lock
flock -n 9 || die 'Another Glacier runner is active.'
CHAIN=${GLACIER_CHAIN:-regtest}
[[ $CHAIN == regtest || $CHAIN == signet || $CHAIN == main ]] || die 'GLACIER_CHAIN must be regtest, signet or main.'
DRIVE=${GLACIER_DRIVE:-/dev/sr0}
[[ $DRIVE =~ ^/dev/sr[0-9]+$ && -b $DRIVE ]] || die 'Set GLACIER_DRIVE to an optical block device, for example /dev/sr0.'
confirm "PROTOTYPE: NO MEANINGFUL FUNDS. This will permanently disable this Ubuntu host's networking, lock kernel module loading until reboot, create seven UNENCRYPTED signer wallets, and burn seven blank CD-Rs. All seven keys share this computer. Network: $CHAIN. Drive: $DRIVE. Use a dedicated disposable installation and a local console." 'AIRGAP PROTOTYPE'
if [[ $CHAIN == main ]]; then confirm 'Mainnet is selected. Recovery and spend tests must pass before any meaningful funds.' 'MAINNET PROTOTYPE'; fi
STATE=/var/lib/glacier2
DATA=$STATE/core-data
CORE=/opt/glacier2/core
mkdir -m 700 "$STATE"
trap cleanup EXIT
trap 'log "Failure at line $LINENO (command suppressed to avoid secret disclosure)."' ERR
printf '%s\n' "$CHAIN" >"$STATE/chain"
printf '%s\n' "$ROOT" >"$STATE/source-location"
for module in install_core airgap wallets backup_cd; do
    log "Starting module: $module"
    # shellcheck source=/dev/null
    source "$ROOT/modules/$module.sh"
    "$module"
    printf '%s\n' "$(date -u +%FT%TZ)" >"$STATE/$module.complete"
    log "Completed module: $module"
done
log 'Seven discs verified. Keep the machine offline. Follow RECOVERY.md before trusting this wallet.'
