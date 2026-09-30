#!/usr/bin/env bash
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
if [[ ${1:-} != --check ]]; then
    if [[ $(cat /proc/sys/kernel/modules_disabled) == 0 ]]; then
        modprobe rfkill
        modprobe nf_tables
    fi
    if ! nft list table inet glacier2 >/dev/null 2>&1; then nft -f /etc/glacier2/airgap.nft; fi
    rfkill block all
    for path in /sys/class/net/*; do
        [[ ${path##*/} == lo ]] && continue
        ip address flush dev "${path##*/}"
        ip -6 address flush dev "${path##*/}"
        ip link set dev "${path##*/}" down
    done
    ip link set lo up
    swapoff -a
    sysctl -w kernel.modules_disabled=1 >/dev/null
fi
[[ $(cat /proc/sys/kernel/modules_disabled) == 1 ]]
# Check actual policies and loopback-only exceptions, not a marker file.
nft -j list table inet glacier2 | python3 -c '
import json,sys
items=json.load(sys.stdin)["nftables"]
chains={i["chain"]["name"]:i["chain"] for i in items if "chain" in i}
assert set(chains)=={"input","output","forward"}
for name,c in chains.items():
    assert c["policy"]=="drop" and c["hook"]==name and c["prio"]==-300
rules=[i["rule"] for i in items if "rule" in i]
assert len(rules)==2
for name,key in [("input","iifname"),("output","oifname")]:
    r=[r for r in rules if r["chain"]==name]
    assert len(r)==1
    assert r[0]["expr"]==[{"match":{"op":"==","left":{"meta":{"key":key}},"right":"lo"}},{"accept":None}]
'
ip -j link show | python3 -c 'import json,sys; links=json.load(sys.stdin); assert any(x["ifname"]=="lo" and "UP" in x["flags"] for x in links); assert all("UP" not in x["flags"] for x in links if x["ifname"]!="lo")'
rfkill --json | python3 -c 'import json,sys; assert all(x["soft"]=="blocked" for x in json.load(sys.stdin).get("rfkilldevices",[]))'
