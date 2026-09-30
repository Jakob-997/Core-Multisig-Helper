#!/usr/bin/env bash
parse_options() {
    TEST_MODE=0
    for option in "$@"; do
        case $option in
            --test) # shellcheck disable=SC2034\n                    TEST_MODE=1;;
            --help|-h)
                printf 'Usage: sudo bash setup.sh [--test]\n--test: real hardening and wallet creation using a 2-of-3 policy, but skips manual paper-share transcription. NEVER fund a test installation.\n'
                exit 0;;
            *) die "Unknown option: $option (use --help)";;
        esac
    done
}

select_modules() {
# shellcheck disable=SC2034\n    MODULES=(install_core airgap wallets desktop_identity)
}
