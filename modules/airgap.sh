#!/usr/bin/env bash
airgap() {
    local path module driver device
    confirm 'Disconnect Ethernet and remove/disable Wi-Fi and Bluetooth hardware now. Software cannot defeat malicious root, kernel or firmware. Continue with persistent software hardening?' 'HARDEN'
    swapoff -a
    [[ $(awk 'END {print NR}' /proc/swaps) == 1 ]] || die 'Swap is still active.'
    ulimit -c 0
    install -d -m 700 /etc/glacier2
    install -m 700 "$ROOT/lib/enforce-airgap.sh" /etc/glacier2/enforce
    install -m 600 "$ROOT/config/airgap.nft" /etc/glacier2/airgap.nft
    # Refuse a collision instead of deleting someone else's nftables table.
    if nft list table inet glacier2 >/dev/null 2>&1; then die 'Firewall table already exists.'; fi
    nft -f /etc/glacier2/airgap.nft
    rfkill block all
    for module in NetworkManager NetworkManager-wait-online systemd-networkd systemd-networkd-wait-online systemd-networkd.socket systemd-resolved wpa_supplicant bluetooth ModemManager avahi-daemon avahi-daemon.socket networking connman iwd; do
        systemctl mask --now "$module" >/dev/null
    done
    # Block every installed NIC/Bluetooth driver, including hardware not present yet.
    : >"$STATE/blocked-modules"
    while IFS= read -r path; do
        module=$(basename "$path")
        module=${module%%.ko*}
        [[ $module =~ ^[a-zA-Z0-9_-]+$ ]] || die 'Unexpected module filename.'
        printf '%s\n' "$module" >>"$STATE/blocked-modules"
    done < <(find /lib/modules -type f \( -path '*/kernel/drivers/net/*' -o -path '*/kernel/drivers/bluetooth/*' \) -name '*.ko*')
    # Keep the boot command line short; comprehensive blocking lives in modprobe.d.
    printf '%s\n' bluetooth btusb cfg80211 mac80211 >"$STATE/boot-blocked-modules"
    # Include actual drivers even when packaged in an unusual directory.
    for path in /sys/class/net/*; do
        [[ ${path##*/} == lo ]] && continue
        if [[ -L $path/device/driver/module ]]; then
            module=$(basename "$(readlink -f "$path/device/driver/module")")
            printf '%s\n' "$module" >>"$STATE/blocked-modules"
            printf '%s\n' "$module" >>"$STATE/boot-blocked-modules"
        fi
    done
    printf '%s\n' bluetooth btusb btrtl btintel btbcm bnep rfcomm cfg80211 mac80211 >>"$STATE/blocked-modules"
    sort -u "$STATE/blocked-modules" -o "$STATE/blocked-modules"
    while read -r module; do printf 'blacklist %s\ninstall %s /bin/false\n' "$module" "$module"; done <"$STATE/blocked-modules" >/etc/modprobe.d/glacier2.conf
    for path in /sys/class/net/*; do
        [[ ${path##*/} == lo ]] && continue
        ip address flush dev "${path##*/}"
        ip -6 address flush dev "${path##*/}"
        ip link set dev "${path##*/}" down
        if [[ -L $path/device/driver && -e $path/device/driver/unbind ]]; then
            driver=$(readlink -f "$path/device/driver")
            device=$(basename "$(readlink -f "$path/device")")
            printf '%s' "$device" >"$driver/unbind"
        fi
    done
    # Loaded drivers may have dependencies; persistent blacklisting plus the
    # firewall/down-state checks remain mandatory if unload is not possible.
    while read -r module; do modprobe -r "$module" 2>/dev/null || true; done <"$STATE/blocked-modules"
    # Expansion of the existing GRUB value is intentional at update-grub time.
    # shellcheck disable=SC2016
    printf 'GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX rfkill.default_state=0 module_blacklist=%s"\n' "$(sort -u "$STATE/boot-blocked-modules" | paste -sd,)" >/etc/default/grub.d/99-glacier2.cfg
    cat >/etc/udev/rules.d/99-glacier2.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="net", KERNEL!="lo", RUN+="/usr/sbin/ip link set dev %k down"
ACTION=="add", SUBSYSTEM=="rfkill", RUN+="/usr/sbin/rfkill block all"
EOF
    install -m 644 "$ROOT/config/glacier2-airgap.service" /etc/systemd/system/glacier2-airgap.service
    systemctl daemon-reload
    systemctl enable glacier2-airgap.service
    udevadm control --reload-rules
    update-initramfs -u -k all
    update-grub
    /etc/glacier2/enforce
    # This cannot be reversed until reboot, even by root. Preload all needed modules first.
    sysctl -w kernel.modules_disabled=1
    [[ $(cat /proc/sys/kernel/modules_disabled) == 1 ]] || die 'Kernel module lock failed.'
    assert_airgap
}

assert_airgap() {
    /etc/glacier2/enforce --check
    [[ $(cat /proc/sys/kernel/modules_disabled) == 1 ]] || die 'Kernel module loading is not locked.'
}
