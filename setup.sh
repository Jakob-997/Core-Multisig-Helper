#!/usr/bin/env bash
set -Eeuo pipefail
set +x
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/options.sh
source "$ROOT/lib/options.sh"
parse_options "$@"
select_modules
[[ $EUID == 0 ]] || die 'Run with sudo bash setup.sh on a disposable Ubuntu installation.'
if [[ $SKIP_CD == 0 ]]; then
    [[ -t 0 && -t 1 ]] || die 'A local terminal is required for swapping CDs. Use --test to skip CDs.'
fi
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
CHAIN=${GLACIER_CHAIN:-main}
[[ $CHAIN == regtest || $CHAIN == signet || $CHAIN == main ]] || die 'GLACIER_CHAIN must be regtest, signet or main.'
DRIVE=${GLACIER_DRIVE:-/dev/sr0}
if [[ $SKIP_CD == 0 ]]; then
    [[ $DRIVE =~ ^/dev/sr[0-9]+$ && -b $DRIVE ]] || die 'Set GLACIER_DRIVE to an optical block device, for example /dev/sr0.'
fi
log "Applying persistent network isolation and creating seven unencrypted $CHAIN signers. No setup confirmations. Prototype: no meaningful funds until recovery/spend tests pass."
if [[ $SKIP_CD == 1 ]]; then log 'TEST FLAG: real hardening and wallet creation; no CD backups. Not a dry run.'; fi
STATE=/var/lib/glacier2
DATA=$STATE/core-data
CORE=/opt/glacier2/core
mkdir -m 700 "$STATE"
trap cleanup EXIT
trap 'log "Failure at line $LINENO (command suppressed to avoid secret disclosure)."' ERR
printf '%s\n' "$CHAIN" >"$STATE/chain"
printf '%s\n' "$ROOT" >"$STATE/source-location"
printf '%s\n' "$SKIP_CD" >"$STATE/skip-cd"
for module in "${MODULES[@]}"; do
    log "Starting module: $module"
    # shellcheck source=/dev/null
    source "$ROOT/modules/$module.sh"
    "$module"
    printf '%s\n' "$(date -u +%FT%TZ)" >"$STATE/$module.complete"
    log "Completed module: $module"
done
if [[ $SKIP_CD == 1 ]]; then
    log 'Setup finished; CDs deliberately skipped. No recovery media exists. Keep offline; do not fund this test setup.'
else
    log 'Seven discs verified. Keep the machine offline. Follow RECOVERY.md before trusting this wallet.'
fi
