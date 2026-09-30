#!/usr/bin/env bash
# Parse before preflight: --test is real hardening/key creation, not a dry run.
parse_options() {
    SKIP_CD=0
    for option in "$@"; do
        case $option in
            --test) SKIP_CD=1;;
            --help|-h)
                printf 'Usage: sudo bash setup.sh [--test]\n--test: perform real airgap and mainnet wallet setup, skip CDs, and show all signer wallets in desktop Bitcoin-Qt. NOT a dry run.\n'
                exit 0;;
            *) die "Unknown option: $option (use --help)";;
        esac
    done
}

select_modules() {
    MODULES=(install_core airgap wallets desktop_identity)
    if [[ $SKIP_CD == 0 ]]; then MODULES+=(backup_cd); fi
}
