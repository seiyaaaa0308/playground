#!/bin/sh
set -eu

chown -R nobody:nogroup /var/lib/misc
exec dnsmasq --keep-in-foreground --conf-file=/etc/dnsmasq.d/lab.conf
