#!/usr/bin/env bash
wallets() {
    assert_airgap
    start_core
    python3 "$ROOT/lib/wallets.py"         "$CORE/bin/bitcoin-cli" "$DATA" "$CHAIN"         "$STATE/public" "$STATE/recovery" /opt/glacier2/shamir-helper "$TEST_MODE"
    assert_airgap
}
