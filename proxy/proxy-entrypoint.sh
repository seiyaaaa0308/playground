#!/bin/sh
set -eu

mkdir -p /etc/nginx/certs
if [ ! -s /etc/nginx/certs/fullchain.pem ] || [ ! -s /etc/nginx/certs/privkey.pem ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
        -keyout /etc/nginx/certs/privkey.pem \
        -out /etc/nginx/certs/fullchain.pem \
        -subj "/CN=web.lab.test" \
        -addext "subjectAltName=DNS:web.lab.test,DNS:localhost,IP:127.0.0.1"
    chmod 644 /etc/nginx/certs/fullchain.pem
    chmod 600 /etc/nginx/certs/privkey.pem
fi

exec nginx -g 'daemon off;'