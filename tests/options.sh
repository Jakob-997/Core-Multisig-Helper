#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
die() { printf '%s\n' "$*" >&2; exit 1; }
# shellcheck source=lib/options.sh
source lib/options.sh
parse_options
select_modules
[[ $SKIP_CD == 0 && ${MODULES[*]} == 'install_core airgap wallets desktop_identity backup_cd' ]]
parse_options --test
select_modules
[[ $SKIP_CD == 1 && ${MODULES[*]} == 'install_core airgap wallets desktop_identity' ]]
if (parse_options --typo) 2>/dev/null; then exit 1; fi
printf 'PASS: default/CD path, --test/no-CD path, and unknown-option rejection.\n'
