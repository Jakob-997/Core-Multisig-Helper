#!/usr/bin/env bash
backup_cd() {
    local n package iso readback sectors
    [[ ! -e $STATE/discs ]] || die 'Disc staging already exists; refusing overwrite.'
    mkdir -m 700 "$STATE/discs"
    for n in {1..7}; do
        assert_airgap
        package=$STATE/discs/signer_$n
        iso=$STATE/discs/signer_$n.iso
        readback=$STATE/discs/readback_$n.iso
        mkdir -m 700 "$package"
        rpc -rpcwallet="signer_$n" backupwallet "$package/wallet.dat"
        [[ -s $package/wallet.dat ]] || die 'Empty backup.'
        cp "$STATE/public/manifest.json" "$STATE/public/descriptors.txt" "$package/"
        cp "$STATE/public/identity.json" "$package/"
        cp "$ROOT/RECOVERY.md" "$package/RECOVERY.md"
        printf 'GLACIER-2 PROTOTYPE\nSigner: %s of 7\nNetwork: %s\nUNENCRYPTED PRIVATE BACKUP. Keep physically separate.\n' "$n" "$CHAIN" >"$package/DISC.txt"
        (cd "$package" && sha256sum wallet.dat manifest.json descriptors.txt identity.json RECOVERY.md DISC.txt >SHA256SUMS)
        [[ $(find "$package" -maxdepth 1 -type f | wc -l) == 7 ]] || die 'Unexpected files in disc package.'
        xorriso -as mkisofs -quiet -R -J -V "GLACIER2_S$n" -o "$iso" "$package"
        [[ $(stat -c %s "$iso") -lt 650000000 ]] || die 'Image too large for supported CD.'
        confirm "Insert a NEW BLANK CD-R in $DRIVE for signer $n. No rewritable media and no existing sessions. Disc will contain exactly one private signer backup." "BURN SIGNER $n"
        if findmnt -rn -S "$DRIVE" >/dev/null; then die 'Optical disc is mounted; unmount it before retrying.'; fi
        xorriso -outdev "$DRIVE" -toc >"$STATE/discs/media_$n.log" 2>&1
        grep -Eq 'Media current:.*CD-R[[:space:]]*$' "$STATE/discs/media_$n.log" || die 'Expected CD-R media (not CD-RW/DVD).'
        grep -Eq 'Media status : is blank' "$STATE/discs/media_$n.log" || die 'Disc is not blank.'
        xorriso -as cdrecord -v dev="$DRIVE" -dao "$iso"
        sync
        eject "$DRIVE"
        printf 'Remove and reinsert signer %s disc. If the desktop mounts it, unmount it before pressing Enter for readback: ' "$n" >/dev/tty
        read -r </dev/tty
        if findmnt -rn -S "$DRIVE" >/dev/null; then die 'Readback disc is mounted; unmount it first.'; fi
        sectors=$(( $(stat -c %s "$iso") / 2048 ))
        dd if="$DRIVE" of="$readback" bs=2048 count="$sectors" iflag=fullblock status=none
        cmp -- "$iso" "$readback"
        mkdir -m 700 "$STATE/discs/readback_$n"
        xorriso -osirrox on -indev "$readback" -extract / "$STATE/discs/readback_$n" >/dev/null 2>&1
        (cd "$STATE/discs/readback_$n" && sha256sum --check --strict SHA256SUMS)
        cmp "$package/wallet.dat" "$STATE/discs/readback_$n/wallet.dat"
        printf '%s signer_%s VERIFIED\n' "$(date -u +%FT%TZ)" "$n" >>"$STATE/discs/verified.log"
        eject "$DRIVE"
        confirm "Label this disc Signer $n of 7 ($CHAIN), and put it aside separately. Keep all discs and staging files offline." "STORED SIGNER $n"
    done
    [[ $(wc -l <"$STATE/discs/verified.log") == 7 ]] || die 'Expected seven verified discs.'
}
