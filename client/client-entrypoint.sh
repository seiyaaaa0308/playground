#!/bin/sh
set -eu

CLIENT_IF="$(ip -o link show | awk -F': ' '$2 ~ /^eth[0-9]+/ { split($2, iface, "@"); print iface[1]; exit }')"

if [ -z "$CLIENT_IF" ]; then
    echo "Could not identify the client network interface." >&2
    exit 1
fi

BOOTSTRAP_ADDR="$(ip -o -4 addr show dev "$CLIENT_IF" | awk '
    $4 ~ /^172\.16\.0\./ {
        split($4, cidr, "/")
        split(cidr[1], octets, ".")
        if (octets[4] >= 128) {
            print $4
            exit
        }
    }
')"
LEASED_ADDR="$(ip -o -4 addr show dev "$CLIENT_IF" | awk '
    $4 ~ /^172\.16\.0\./ {
        split($4, cidr, "/")
        split(cidr[1], octets, ".")
        if (octets[4] >= 10 && octets[4] <= 99) {
            print $4
            exit
        }
    }
')"

if [ -z "$BOOTSTRAP_ADDR" ] && [ -z "$LEASED_ADDR" ]; then
    echo "Could not identify a Docker bootstrap address or existing DHCP lease." >&2
    exit 1
fi

dhclient -v -1 "$CLIENT_IF"
ip route replace default via 172.16.0.1
if [ -n "$BOOTSTRAP_ADDR" ] && ip -o -4 addr show dev "$CLIENT_IF" | grep -Fq " $BOOTSTRAP_ADDR "; then
    ip -4 addr del "$BOOTSTRAP_ADDR" dev "$CLIENT_IF"
fi

exec "$@"
