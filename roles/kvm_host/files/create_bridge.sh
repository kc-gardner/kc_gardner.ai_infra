#!/usr/bin/env bash
# Move a physical NIC onto a new NetworkManager bridge, keeping its IPv4 config
# and MAC address (so a DHCP reservation keeps the same IP).
# Rolls back to the original connection if the bridge gets no IPv4 address.
set -euo pipefail

BRIDGE="$1"
IFACE="$2"
MAC="$3"
PORT="${BRIDGE}-port-${IFACE}"

ORIG_CON="$(nmcli -g GENERAL.CONNECTION device show "$IFACE")"
if [[ -z "$ORIG_CON" ]]; then
  echo "No active connection on $IFACE" >&2
  exit 1
fi

METHOD="$(nmcli -g ipv4.method connection show "$ORIG_CON")"
IPV4_ARGS=(ipv4.method auto)
if [[ "$METHOD" == "manual" ]]; then
  IPV4_ARGS=(
    ipv4.method manual
    ipv4.addresses "$(nmcli -g ipv4.addresses connection show "$ORIG_CON")"
    ipv4.gateway "$(nmcli -g ipv4.gateway connection show "$ORIG_CON")"
    ipv4.dns "$(nmcli -g ipv4.dns connection show "$ORIG_CON")"
  )
fi

rollback() {
  echo "Bridge failed, rolling back to '$ORIG_CON'" >&2
  nmcli connection delete "$PORT" || true
  nmcli connection delete "$BRIDGE" || true
  nmcli connection modify "$ORIG_CON" connection.autoconnect yes
  nmcli connection up "$ORIG_CON"
  exit 1
}

nmcli connection add type bridge ifname "$BRIDGE" con-name "$BRIDGE" \
  bridge.stp no bridge.mac-address "$MAC" \
  "${IPV4_ARGS[@]}" ipv6.method auto
nmcli connection add type ethernet ifname "$IFACE" con-name "$PORT" \
  controller "$BRIDGE" port-type bridge
nmcli connection modify "$ORIG_CON" connection.autoconnect no

nmcli connection up "$PORT" || rollback
nmcli connection up "$BRIDGE" || rollback

for _ in $(seq 1 30); do
  if ip -4 -o addr show dev "$BRIDGE" | grep -q 'inet '; then
    echo "Bridge $BRIDGE is up"
    exit 0
  fi
  sleep 2
done

rollback
