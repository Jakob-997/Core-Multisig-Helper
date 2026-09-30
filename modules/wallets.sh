#!/usr/bin/env bash
wallets() {
    assert_airgap
    start_core
    python3 "$ROOT/lib/wallets.py" "$CORE/bin/bitcoin-cli" "$DATA" "$CHAIN" "$STATE/public"
    assert_airgap
}
