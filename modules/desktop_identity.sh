#!/usr/bin/env bash
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

desktop_identity() {
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
    install -m 755 "$ROOT/lib/launch-qt.sh" /opt/glacier2/identity/launch-qt

    local desktop_mode=watch-only
    if [[ $TEST_MODE == 1 ]]; then desktop_mode=test-signer; fi
    desktop_user python3 /opt/glacier2/identity/setup.py apply /opt/glacier2/identity "$CHAIN" "$desktop_mode"

    if [[ $TEST_MODE == 1 ]]; then
        local desktop_data="$DESKTOP_HOME/.local/share/glacier2/core"
        local desktop_chain_dir="$desktop_data"
        local desktop_wallet_dir
        [[ $CHAIN == main ]] || desktop_chain_dir="$desktop_data/$CHAIN"
        desktop_wallet_dir="$desktop_chain_dir/wallets"
        rpc -rpcwallet=signer getwalletinfo | jq -e '.private_keys_enabled == true' >/dev/null
        install -d -m 700 -o "$DESKTOP_UID" -g "$DESKTOP_GID" "$desktop_wallet_dir/signer"
        rpc -rpcwallet=signer backupwallet "$desktop_wallet_dir/signer/wallet.dat"
        chown "$DESKTOP_UID:$DESKTOP_GID" "$desktop_wallet_dir/signer/wallet.dat"
        chmod 600 "$desktop_wallet_dir/signer/wallet.dat"
        log 'TEST MODE: encrypted signer wallet is available in desktop Bitcoin-Qt for inspection. Do not fund this setup.'
    fi

    cp /opt/glacier2/identity/identity.json "$STATE/public/identity.json"
    log "Recognition code: $(jq -r .code /opt/glacier2/identity/identity.json)"
    log "Background color: $(jq -r .color /opt/glacier2/identity/identity.json)"
    log 'Record the code/color on separate paper and check lock/unlock. Visual cues do not prove integrity or prevent exfiltration.'
}
