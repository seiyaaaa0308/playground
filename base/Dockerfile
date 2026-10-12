FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    certbot \
    conntrack \
    curl \
    dbus \
    dnsutils \
    dnsmasq \
    firewalld \
    isc-dhcp-client \
    iproute2 \
    iptables \
    iputils-ping \
    less \
    net-tools \
    nginx \
    nftables \
    openssl \
    procps \
    tcpdump \
    traceroute \
    vim-tiny \
    && rm -rf /var/lib/apt/lists/*

COPY router/router-entrypoint.sh /usr/local/sbin/router-entrypoint
COPY proxy/proxy-entrypoint.sh /usr/local/sbin/proxy-entrypoint
COPY client/client-entrypoint.sh /usr/local/sbin/client-entrypoint
COPY dhcp/dhcp-entrypoint.sh /usr/local/sbin/dhcp-entrypoint
RUN rm -f /etc/nginx/sites-enabled/default \
    && sed -i 's/worker_processes auto;/worker_processes 1;/' /etc/nginx/nginx.conf \
    && chmod 0755 /usr/local/sbin/router-entrypoint /usr/local/sbin/proxy-entrypoint \
        /usr/local/sbin/client-entrypoint /usr/local/sbin/dhcp-entrypoint

CMD ["nginx", "-g", "daemon off;"]