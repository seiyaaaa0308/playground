#!/bin/sh
set -eu

CLIENT_IF="$(ip -o -4 addr show | awk '$4 ~ /^172\.16\.0\./ { print $2; exit }')"
SERVER_IF="$(ip -o -4 addr show | awk '$4 ~ /^172\.24\.0\./ { print $2; exit }')"

if [ -z "$CLIENT_IF" ] || [ -z "$SERVER_IF" ]; then
    echo "Could not identify the client and server interfaces." >&2
    exit 1
fi

mkdir -p /run/dbus
rm -f /run/dbus/pid /run/dbus/system_bus_socket
dbus-daemon --system --fork
firewalld --nofork --nopid &

ready=0
for attempt in $(seq 1 30); do
    if firewall-cmd --state >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done

if [ "$ready" -ne 1 ]; then
    echo "firewalld did not become ready." >&2
    exit 1
fi

ensure_zone() {
    if ! firewall-cmd --permanent --get-zones | tr ' ' '\n' | grep -Fxq "$1"; then
        firewall-cmd --permanent --new-zone="$1"
    fi
}

ensure_policy() {
    if ! firewall-cmd --permanent --get-policies | tr ' ' '\n' | grep -Fxq "$1"; then
        firewall-cmd --permanent --new-policy="$1"
    fi
}

ensure_forward_port() {
    if ! firewall-cmd --permanent --zone=client --query-forward-port="$1" >/dev/null 2>&1; then
        firewall-cmd --permanent --zone=client --add-forward-port="$1"
    fi
}

ensure_zone client
ensure_zone server
ensure_policy client-to-server

if ! firewall-cmd --permanent --zone=client --query-interface="$CLIENT_IF" >/dev/null; then
    firewall-cmd --permanent --zone=client --add-interface="$CLIENT_IF"
fi
if ! firewall-cmd --permanent --zone=server --query-interface="$SERVER_IF" >/dev/null; then
    firewall-cmd --permanent --zone=server --add-interface="$SERVER_IF"
fi
if ! firewall-cmd --permanent --policy=client-to-server --list-all | grep -Eq '^  ingress-zones:.*client'; then
    firewall-cmd --permanent --policy=client-to-server --add-ingress-zone=client
fi
if ! firewall-cmd --permanent --policy=client-to-server --list-all | grep -Eq '^  egress-zones:.*server'; then
    firewall-cmd --permanent --policy=client-to-server --add-egress-zone=server
fi
if [ "$(firewall-cmd --permanent --policy=client-to-server --get-target)" != ACCEPT ]; then
    firewall-cmd --permanent --policy=client-to-server --set-target=ACCEPT
fi
if ! firewall-cmd --permanent --policy=client-to-server --query-masquerade >/dev/null; then
    firewall-cmd --permanent --policy=client-to-server --add-masquerade
fi

ensure_forward_port port=8080:proto=tcp:toaddr=172.24.0.10:toport=80
ensure_forward_port port=8443:proto=tcp:toaddr=172.24.0.10:toport=443
ensure_forward_port port=80:proto=tcp:toaddr=172.24.0.10:toport=80
ensure_forward_port port=443:proto=tcp:toaddr=172.24.0.10:toport=443
firewall-cmd --reload

echo "Router ready: $CLIENT_IF (client) -> $SERVER_IF (server)"
exec "$@"